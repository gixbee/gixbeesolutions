use super::*;
use axum::routing::delete;
use sqlx::PgConnection;

pub(super) const UNAVAILABLE_TITLE: &str = "Unavailable";

pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/vendor/calendar/{business}", get(entries).post(add))
        .route("/vendor/calendar/{business}/overview", get(overview))
        .route(
            "/vendor/calendar/{business}/unavailable",
            post(block_day).delete(release_day),
        )
        .route("/vendor/calendar/{business}/{entry}", delete(cancel).put(edit))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntryInput {
    title: String,
    start_at: DateTime<Utc>,
    end_at: DateTime<Utc>,
}

#[derive(Deserialize, Default)]
struct OverviewQuery {
    service: Option<String>,
}

async fn owner(conn: &mut PgConnection, business: Uuid, uid: Uuid, lock: bool) -> AppResult<()> {
    let query = format!(
        r#"SELECT id FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='SERVICE'
           AND ("serviceType"::text IN ('PHOTOGRAPHY','CATERING')
             OR "eventServices" ?| ARRAY['PHOTOGRAPHY','CATERING']) {}"#,
        if lock { "FOR UPDATE" } else { "" },
    );
    let owned: Option<Uuid> = sqlx::query_scalar(&query)
        .bind(business)
        .bind(uid)
        .fetch_optional(&mut *conn)
        .await?;
    if owned.is_none() {
        return Err(AppError::NotFound("Business calendar not found".into()));
    }
    Ok(())
}

async fn entries(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
) -> AppResult<Json<Vec<Value>>> {
    let mut conn = state.db.acquire().await?;
    owner(&mut conn, business, Uuid::parse_str(&user.user_id)?, false).await?;
    let data = sqlx::query_scalar(
        r#"SELECT to_jsonb(e) FROM event_vendor_calendar e WHERE "businessId"=$1
           AND e.title <> 'Unavailable'
           ORDER BY (e."endAt">NOW() AND e."cancelledAt" IS NULL) DESC, e."startAt" DESC LIMIT 200"#,
    )
    .bind(business).fetch_all(&mut *conn).await?;
    Ok(Json(data))
}

/// Read-only owner schedule, including existing Gixbee bookings and manually
/// entered outside shoots. The owner can view only their own business.
/// No new SQL schema is required; booking rows are projected from event_quotes.
async fn overview(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
    Query(query): Query<OverviewQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let service = query
        .service
        .as_deref()
        .filter(|value| !value.is_empty())
        .unwrap_or("PHOTOGRAPHY");
    if !matches!(service, "PHOTOGRAPHY" | "CATERING") {
        return Err(AppError::BadRequest(
            "Choose photography or catering".into(),
        ));
    }
    let mut conn = state.db.acquire().await?;
    owner(&mut conn, business, Uuid::parse_str(&user.user_id)?, false).await?;
    let mut rows: Vec<Value> = sqlx::query_scalar(
        r#"SELECT to_jsonb(e) || jsonb_build_object('source','offline')
           FROM event_vendor_calendar e
           WHERE e."businessId"=$1 AND e."cancelledAt" IS NULL
             AND e.title <> 'Unavailable'
           ORDER BY e."startAt" DESC LIMIT 500"#,
    ).bind(business).fetch_all(&mut *conn).await?;
    let booked: Vec<Value> = sqlx::query_scalar(
        r#"SELECT jsonb_build_object(
            'id', q.id, 'source', 'gixbee',
            'title', p."eventType",
            'startAt', COALESCE(q."intervalStart",p."startTime"),
            'endAt', COALESCE(q."intervalEnd",p."endTime"),
            'status', q.status::text,
            'location', p.location,
            'guestCount', p."guestCount",
            'planId', p.id)
          FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
          WHERE q."businessId"=$1 AND q."serviceType"=$2
            AND q.status IN ('CONFIRMED','CANCEL_REQUESTED','COMPLETED')
            AND p."cancelledAt" IS NULL
          ORDER BY p."startTime" DESC LIMIT 500"#,
    )
    .bind(business)
    .bind(service)
    .fetch_all(&mut *conn)
    .await?;
    rows.extend(booked);
    Ok(Json(rows))
}

async fn add(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
    Json(input): Json<EntryInput>,
) -> AppResult<Json<Value>> {
    let title = input.title.trim();
    if title.is_empty()
        || title == UNAVAILABLE_TITLE
        || title.chars().count() > 160
        || input.start_at <= Utc::now()
        || input.end_at <= input.start_at
        || input.end_at - input.start_at > chrono::Duration::days(14)
    {
        return Err(AppError::BadRequest(
            "Enter a title and future booking times".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    owner(&mut tx, business, Uuid::parse_str(&user.user_id)?, true).await?;
    check_overlap(&mut tx, business, input.start_at, input.end_at).await?;
    let confirmed: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
             WHERE q."businessId"=$1 AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
             AND q."serviceType"<>'HALL'
             AND COALESCE(q."intervalStart",p."startTime")<$3
             AND COALESCE(q."intervalEnd",p."endTime")>$2)"#,
    )
    .bind(business)
    .bind(input.start_at)
    .bind(input.end_at)
    .fetch_one(&mut *tx)
    .await?;
    if confirmed {
        return Err(AppError::Conflict(
            "A confirmed booking already uses this time".into(),
        ));
    }
    let entry = sqlx::query_scalar(
        r#"INSERT INTO event_vendor_calendar (id,"businessId",title,"startAt","endAt")
           VALUES ($1,$2,$3,$4,$5) RETURNING to_jsonb(event_vendor_calendar)"#,
    )
    .bind(Uuid::new_v4())
    .bind(business)
    .bind(title)
    .bind(input.start_at)
    .bind(input.end_at)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(entry))
}

/// Owners can reschedule an outside shoot without creating a duplicate.
/// The business row is locked, then the original entry is excluded from
/// interval collision checks. Confirmed Gixbee bookings remain protected.
async fn edit(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business, entry)): Path<(Uuid, Uuid)>,
    Json(input): Json<EntryInput>,
) -> AppResult<Json<Value>> {
    let title = input.title.trim();
    if title.is_empty() || title == UNAVAILABLE_TITLE || title.chars().count() > 160
        || input.start_at <= Utc::now()
        || input.end_at <= input.start_at
        || input.end_at - input.start_at > chrono::Duration::days(14)
    {
        return Err(AppError::BadRequest(
            "Enter a title and future booking times".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    owner(&mut tx, business, Uuid::parse_str(&user.user_id)?, true).await?;
    let existing: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM event_vendor_calendar WHERE "businessId"=$1
           AND id=$2 AND "cancelledAt" IS NULL FOR UPDATE"#,
    ).bind(business).bind(entry).fetch_optional(&mut *tx).await?;
    if existing.is_none() {
        return Err(AppError::NotFound("Outside booking not found".into()));
    }
    check_overlap_except(&mut tx, business, input.start_at, input.end_at, Some(entry)).await?;
    let confirmed: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p
             ON p.id=q."planId"
             WHERE q."businessId"=$1
               AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
               AND q."serviceType"<>'HALL'
               AND COALESCE(q."intervalStart",p."startTime")<$3
               AND COALESCE(q."intervalEnd",p."endTime")>$2)"#,
    ).bind(business).bind(input.start_at).bind(input.end_at)
       .fetch_one(&mut *tx).await?;
    if confirmed {
        return Err(AppError::Conflict(
            "A confirmed booking already uses this time".into(),
        ));
    }
    let result: Value = sqlx::query_scalar(
        r#"UPDATE event_vendor_calendar
           SET title=$3,"startAt"=$4,"endAt"=$5
           WHERE "businessId"=$1 AND id=$2 AND "cancelledAt" IS NULL
           RETURNING to_jsonb(event_vendor_calendar)"#,
    ).bind(business).bind(entry).bind(title)
      .bind(input.start_at).bind(input.end_at)
      .fetch_one(&mut *tx).await?;
    tx.commit().await?;
    Ok(Json(result))
}

async fn cancel(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business, entry)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let mut tx = state.db.begin().await?;
    owner(&mut tx, business, Uuid::parse_str(&user.user_id)?, true).await?;
    let updated = sqlx::query(
        r#"UPDATE event_vendor_calendar SET "cancelledAt"=COALESCE("cancelledAt",NOW())
           WHERE id=$1 AND "businessId"=$2"#,
    )
    .bind(entry)
    .bind(business)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound("Calendar booking not found".into()));
    }
    tx.commit().await?;
    Ok(Json(json!({"cancelled": true})))
}

pub(super) async fn check_overlap(
    conn: &mut PgConnection,
    business: Uuid,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> AppResult<()> {
    check_overlap_except(conn, business, start, end, None).await
}

async fn check_overlap_except(
    conn: &mut PgConnection,
    business: Uuid,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    exclude: Option<Uuid>,
) -> AppResult<()> {
    let conflict: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_vendor_calendar WHERE "businessId"=$1
           AND "cancelledAt" IS NULL AND "startAt"<$3 AND "endAt">$2
           AND ($4::uuid IS NULL OR id<>$4))"#,
    )
    .bind(business)
    .bind(start)
    .bind(end)
    .bind(exclude)
    .fetch_one(conn)
    .await?;
    if conflict {
        return Err(AppError::Conflict(
            "The provider has a calendar booking at this time".into(),
        ));
    }
    Ok(())
}

fn parse_day(date: &str) -> AppResult<chrono::NaiveDate> {
    let key = date
        .get(..10)
        .ok_or_else(|| AppError::BadRequest("A valid date is required".into()))?;
    chrono::NaiveDate::parse_from_str(key, "%Y-%m-%d")
        .map_err(|_| AppError::BadRequest("A valid date is required".into()))
}

fn ist_day(day: chrono::NaiveDate) -> AppResult<(DateTime<Utc>, DateTime<Utc>)> {
    use chrono::TimeZone;
    let offset = chrono::FixedOffset::east_opt(19800).unwrap();
    let next = day
        .succ_opt()
        .ok_or_else(|| AppError::BadRequest("A valid date is required".into()))?;
    let start = day
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_local_timezone(offset)
        .single()
        .ok_or_else(|| AppError::BadRequest("A valid date is required".into()))?;
    let end = next
        .and_hms_opt(0, 0, 0)
        .unwrap()
        .and_local_timezone(offset)
        .single()
        .ok_or_else(|| AppError::BadRequest("A valid date is required".into()))?;
    Ok((start.with_timezone(&Utc), end.with_timezone(&Utc)))
}

/// Full IST day on `event_vendor_calendar`. The title is reserved so the row
/// is unavailability, not an outside shoot. The caller holds the transaction.
pub(super) async fn set_unavailable_day(
    conn: &mut PgConnection,
    business: Uuid,
    actor: Uuid,
    day: chrono::NaiveDate,
    add: bool,
) -> AppResult<()> {
    let owned: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='SERVICE'
           AND "serviceType"::text IS DISTINCT FROM 'HALL' FOR UPDATE"#,
    )
    .bind(business)
    .bind(actor)
    .fetch_optional(&mut *conn)
    .await?;
    if owned.is_none() {
        return Err(AppError::NotFound("Business calendar not found".into()));
    }
    let (start, end) = ist_day(day)?;
    if add {
        let exists: bool = sqlx::query_scalar(
            r#"SELECT EXISTS(SELECT 1 FROM event_vendor_calendar
               WHERE "businessId"=$1 AND "cancelledAt" IS NULL AND title=$2
                 AND "startAt"=$3 AND "endAt"=$4)"#,
        )
        .bind(business)
        .bind(UNAVAILABLE_TITLE)
        .bind(start)
        .bind(end)
        .fetch_one(&mut *conn)
        .await?;
        if exists {
            return Ok(());
        }
        let confirmed: bool = sqlx::query_scalar(
            r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
               WHERE q."businessId"=$1 AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
                 AND q."serviceType"<>'HALL'
                 AND COALESCE(q."intervalStart",p."startTime")<$3
                 AND COALESCE(q."intervalEnd",p."endTime")>$2)"#,
        )
        .bind(business)
        .bind(start)
        .bind(end)
        .fetch_one(&mut *conn)
        .await?;
        if confirmed {
            return Err(AppError::Conflict(
                "This date has a confirmed event. Resolve the booking before marking it unavailable".into(),
            ));
        }
        check_overlap(conn, business, start, end).await?;
        sqlx::query(
            r#"INSERT INTO event_vendor_calendar (id,"businessId",title,"startAt","endAt")
               VALUES ($1,$2,$3,$4,$5)"#,
        )
        .bind(Uuid::new_v4())
        .bind(business)
        .bind(UNAVAILABLE_TITLE)
        .bind(start)
        .bind(end)
        .execute(&mut *conn)
        .await?;
    } else {
        sqlx::query(
            r#"UPDATE event_vendor_calendar SET "cancelledAt"=COALESCE("cancelledAt",NOW())
               WHERE "businessId"=$1 AND title=$2 AND "cancelledAt" IS NULL
                 AND "startAt"=$3 AND "endAt"=$4"#,
        )
        .bind(business)
        .bind(UNAVAILABLE_TITLE)
        .bind(start)
        .bind(end)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

#[derive(Deserialize)]
struct DayBody {
    date: String,
}

#[derive(Deserialize)]
struct DayQuery {
    date: String,
}

async fn block_day(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
    Json(body): Json<DayBody>,
) -> AppResult<Json<Value>> {
    let mut tx = state.db.begin().await?;
    set_unavailable_day(
        &mut tx,
        business,
        Uuid::parse_str(&user.user_id)?,
        parse_day(&body.date)?,
        true,
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"blocked": true})))
}

async fn release_day(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
    Query(query): Query<DayQuery>,
) -> AppResult<Json<Value>> {
    let mut tx = state.db.begin().await?;
    set_unavailable_day(
        &mut tx,
        business,
        Uuid::parse_str(&user.user_id)?,
        parse_day(&query.date)?,
        false,
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"blocked": false})))
}
