use super::*;
use axum::routing::delete;
use sqlx::PgConnection;

pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/vendor/calendar/{business}", get(entries).post(add))
        .route("/vendor/calendar/{business}/{entry}", delete(cancel))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntryInput {
    title: String,
    start_at: DateTime<Utc>,
    end_at: DateTime<Utc>,
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
           ORDER BY (e."endAt">NOW() AND e."cancelledAt" IS NULL) DESC, e."startAt" DESC LIMIT 200"#,
    )
    .bind(business).fetch_all(&mut *conn).await?;
    Ok(Json(data))
}

async fn add(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business): Path<Uuid>,
    Json(input): Json<EntryInput>,
) -> AppResult<Json<Value>> {
    let title = input.title.trim();
    if title.is_empty()
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
    let conflict: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_vendor_calendar WHERE "businessId"=$1
           AND "cancelledAt" IS NULL AND "startAt"<$3 AND "endAt">$2)"#,
    )
    .bind(business)
    .bind(start)
    .bind(end)
    .fetch_one(conn)
    .await?;
    if conflict {
        return Err(AppError::Conflict(
            "The provider has a calendar booking at this time".into(),
        ));
    }
    Ok(())
}
