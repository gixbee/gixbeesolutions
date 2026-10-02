//! Hall enquiry lifecycle (owner approve/decline/assign). Separate from customer quote accept.
use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::halls::audit::{bump_hall_caches, write_audit};
use crate::halls::availability::{
    acquire_hall_scope_locks, assign_hold_expires_at, availability_check,
    release_holds_for_enquiry, Interval,
};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/{business_id}/hall-enquiries",
            get(list_business_enquiries),
        )
        .route(
            "/{business_id}/hall-enquiries/{enquiry_id}/owner-approve",
            post(owner_approve),
        )
        .route(
            "/{business_id}/hall-enquiries/{enquiry_id}/owner-decline",
            post(owner_decline),
        )
        .route(
            "/{business_id}/hall-enquiries/{enquiry_id}/assign-hall",
            post(assign_hall),
        )
        .route(
            "/{business_id}/halls/{hall_id}/enquiries",
            get(list_hall_enquiries),
        )
}

async fn require_owner(db: &sqlx::PgPool, business_id: Uuid, uid: Uuid) -> AppResult<()> {
    let owner: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT "ownerId" FROM businesses
           WHERE id = $1 AND type = 'SERVICE' AND "serviceType"::text = 'HALL'"#,
    )
    .bind(business_id)
    .fetch_optional(db)
    .await?;
    match owner {
        Some(o) if o == uid => Ok(()),
        Some(_) => Err(AppError::Forbidden(
            "Only the business owner may manage enquiries".into(),
        )),
        None => Err(AppError::NotFound("Hall business not found".into())),
    }
}

/// Owner check after `businesses` is locked. The unlocked `require_owner` call
/// only avoids starting a transaction for an obvious rejection.
async fn recheck_locked_owner(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    business_id: Uuid,
    uid: Uuid,
) -> AppResult<()> {
    let owner: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT "ownerId" FROM businesses
           WHERE id = $1 AND type = 'SERVICE' AND "serviceType"::text = 'HALL'"#,
    )
    .bind(business_id)
    .fetch_optional(&mut **tx)
    .await?;
    match owner {
        Some(owner) if owner == uid => Ok(()),
        Some(_) => Err(AppError::Forbidden(
            "Only the business owner may manage enquiries".into(),
        )),
        None => Err(AppError::NotFound("Hall business not found".into())),
    }
}

/// Create hall enquiries for eligible HALL businesses (idempotent UNIQUE plan+business).
pub async fn ensure_enquiries_for_plan(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    plan_id: Uuid,
    customer_id: Uuid,
    city_id: Option<Uuid>,
    services: &[String],
) -> AppResult<usize> {
    if !services.iter().any(|s| s == "HALL") {
        return Ok(0);
    }
    let businesses = sqlx::query(
        r#"SELECT id, "ownerId" FROM businesses
           WHERE type = 'SERVICE' AND status = 'VERIFIED'
             AND "serviceType"::text = 'HALL'
             AND "ownerId" <> $1
             AND ($2::uuid IS NULL OR "cityId" = $2)
           ORDER BY id
           LIMIT 200"#,
    )
    .bind(customer_id)
    .bind(city_id)
    .fetch_all(&mut **tx)
    .await?;
    let mut created = 0usize;
    for b in businesses {
        let bid: Uuid = b.get("id");
        let owner: Uuid = b.get("ownerId");
        let inserted = sqlx::query(
            r#"INSERT INTO hall_enquiries (id, "eventPlanId", "businessId", status)
               VALUES ($1, $2, $3, 'PENDING_OWNER')
               ON CONFLICT ("eventPlanId", "businessId") DO NOTHING
               RETURNING id"#,
        )
        .bind(Uuid::new_v4())
        .bind(plan_id)
        .bind(bid)
        .fetch_optional(&mut **tx)
        .await?;
        if let Some(row) = inserted {
            created += 1;
            let eid: Uuid = row.get("id");
            write_audit(
                &mut **tx,
                bid,
                None,
                "enquiry",
                &eid.to_string(),
                "create",
                customer_id,
                json!({"planId": plan_id}),
            )
            .await?;
            crate::outbox::notify(
                &mut *tx,
                plan_id,
                owner,
                "New hall enquiry",
                "A customer needs a hall. Open Enquiries to review and assign a hall.",
                json!({"type": "hall_enquiry_update", "planId": plan_id, "enquiryId": eid, "businessId": bid}),
            )
            .await?;
            bump_hall_caches(&mut *tx, bid, None).await?;
        }
    }
    Ok(created)
}

async fn list_business_enquiries(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_owner(&state.db, business_id, uid).await?;
    let rows = sqlx::query(
        r#"SELECT to_jsonb(e) || jsonb_build_object(
             'eventType', p."eventType",
             'startTime', p."startTime",
             'endTime', p."endTime",
             'guestCount', p."guestCount",
             'location', p.location,
             'hallName', h.name,
             'venueTimezone', COALESCE(v.timezone, 'Asia/Kolkata')
           ) AS data
           FROM hall_enquiries e
           JOIN event_plans p ON p.id = e."eventPlanId"
           LEFT JOIN business_halls h ON h.id = e."assignedHallId"
           LEFT JOIN business_hall_venue v ON v."businessId" = e."businessId"
           WHERE e."businessId" = $1
           ORDER BY e."createdAt" DESC
           LIMIT 200"#,
    )
    .bind(business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}

async fn list_hall_enquiries(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let owner: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT "ownerId" FROM businesses WHERE id = $1 AND "serviceType"::text = 'HALL'"#,
    )
    .bind(business_id)
    .fetch_optional(&state.db)
    .await?;
    let is_owner = owner == Some(uid);
    let is_op: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM business_hall_operators
            WHERE "hallId" = $1 AND "userId" = $2
        )"#,
    )
    .bind(hall_id)
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if !is_owner && !is_op {
        return Err(AppError::Forbidden(
            "You cannot view enquiries for this hall".into(),
        ));
    }
    let rows = sqlx::query(
        r#"SELECT to_jsonb(e) || jsonb_build_object(
             'eventType', p."eventType",
             'startTime', p."startTime",
             'endTime', p."endTime",
             'guestCount', p."guestCount",
             'readOnly', $3::boolean,
             'venueTimezone', COALESCE(v.timezone, 'Asia/Kolkata')
           ) AS data
           FROM hall_enquiries e
           JOIN event_plans p ON p.id = e."eventPlanId"
           LEFT JOIN business_hall_venue v ON v."businessId" = e."businessId"
           WHERE e."businessId" = $1 AND e."assignedHallId" = $2
           ORDER BY e."createdAt" DESC
           LIMIT 100"#,
    )
    .bind(business_id)
    .bind(hall_id)
    .bind(!is_owner)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}

/// Lock the parent event before the business, venue, or hall locks.
/// `acquire_hall_scope_locks` must be the next lock: it takes `businesses`,
/// then the venue, then halls. Reject a cancelled event so approve, assign,
/// and hold creation cannot race ahead of whole-event cancel.
async fn lock_open_event_for_enquiry(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    enquiry_id: Uuid,
) -> AppResult<Uuid> {
    let plan_id: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT "eventPlanId" FROM hall_enquiries WHERE id = $1"#,
    )
    .bind(enquiry_id)
    .fetch_optional(&mut **tx)
    .await?;
    let plan_id = plan_id.ok_or_else(|| AppError::NotFound("Enquiry not found".into()))?;
    let cancelled_at: Option<DateTime<Utc>> = sqlx::query_scalar::<_, Option<DateTime<Utc>>>(
        r#"SELECT "cancelledAt" FROM event_plans WHERE id = $1 FOR UPDATE"#,
    )
    .bind(plan_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Event not found".into()))?;
    if cancelled_at.is_some() {
        return Err(AppError::Conflict(
            "This event has been cancelled".into(),
        ));
    }
    Ok(plan_id)
}

async fn owner_approve(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, enquiry_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    transition_owner(
        state,
        user,
        business_id,
        enquiry_id,
        "PENDING_OWNER",
        "OWNER_APPROVED",
        "approve",
    )
    .await
}

async fn owner_decline(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, enquiry_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_owner(&state.db, business_id, uid).await?;
    let mut tx = state.db.begin().await?;
    lock_open_event_for_enquiry(&mut tx, enquiry_id).await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[])).await?;
    recheck_locked_owner(&mut tx, business_id, uid).await?;
    let row = sqlx::query(
        r#"SELECT status FROM hall_enquiries WHERE id = $1 AND "businessId" = $2 FOR UPDATE"#,
    )
    .bind(enquiry_id)
    .bind(business_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Enquiry not found".into()))?;
    if row.get::<String, _>("status") != "PENDING_OWNER" {
        return Err(AppError::Conflict(
            "Only a pending enquiry can be declined".into(),
        ));
    }
    sqlx::query(
        r#"UPDATE hall_enquiries SET status = 'OWNER_DECLINED', "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(enquiry_id)
    .execute(&mut *tx)
    .await?;
    release_holds_for_enquiry(&mut *tx, enquiry_id).await?;
    write_audit(
        &mut *tx,
        business_id,
        None,
        "enquiry",
        &enquiry_id.to_string(),
        "decline",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, None).await?;
    let customer: Uuid = sqlx::query_scalar(
        r#"SELECT p."customerId" FROM event_plans p
           JOIN hall_enquiries e ON e."eventPlanId" = p.id WHERE e.id = $1"#,
    )
    .bind(enquiry_id)
    .fetch_one(&mut *tx)
    .await?;
    crate::outbox::notify(
        &mut tx,
        enquiry_id,
        customer,
        "Hall enquiry declined",
        "A hall business declined your enquiry.",
        json!({"type": "hall_enquiry_update", "enquiryId": enquiry_id, "status": "OWNER_DECLINED"}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"status": "OWNER_DECLINED"})))
}

async fn transition_owner(
    state: AppState,
    user: AuthUser,
    business_id: Uuid,
    enquiry_id: Uuid,
    from: &str,
    to: &str,
    action: &str,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_owner(&state.db, business_id, uid).await?;
    let mut tx = state.db.begin().await?;
    lock_open_event_for_enquiry(&mut tx, enquiry_id).await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[])).await?;
    recheck_locked_owner(&mut tx, business_id, uid).await?;
    let row = sqlx::query(
        r#"SELECT status FROM hall_enquiries WHERE id = $1 AND "businessId" = $2 FOR UPDATE"#,
    )
    .bind(enquiry_id)
    .bind(business_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Enquiry not found".into()))?;
    if row.get::<String, _>("status") != from {
        return Err(AppError::Conflict(format!(
            "Enquiry must be {from} to {action}"
        )));
    }
    sqlx::query(
        r#"UPDATE hall_enquiries SET status = $2, "updatedAt" = NOW() WHERE id = $1"#,
    )
    .bind(enquiry_id)
    .bind(to)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        None,
        "enquiry",
        &enquiry_id.to_string(),
        action,
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, None).await?;
    tx.commit().await?;
    Ok(Json(json!({"status": to})))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AssignBody {
    hall_id: Uuid,
    proposed_start_at: String,
    proposed_end_at: String,
}

async fn assign_hall(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, enquiry_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<AssignBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_owner(&state.db, business_id, uid).await?;
    let start = DateTime::parse_from_rfc3339(&body.proposed_start_at)
        .map(|d| d.with_timezone(&Utc))
        .map_err(|_| AppError::BadRequest("proposedStartAt must be RFC3339".into()))?;
    let end = DateTime::parse_from_rfc3339(&body.proposed_end_at)
        .map(|d| d.with_timezone(&Utc))
        .map_err(|_| AppError::BadRequest("proposedEndAt must be RFC3339".into()))?;
    let interval = Interval::new(start, end)?;

    let mut tx = state.db.begin().await?;
    lock_open_event_for_enquiry(&mut tx, enquiry_id).await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[body.hall_id])).await?;
    recheck_locked_owner(&mut tx, business_id, uid).await?;

    let enq = sqlx::query(
        r#"SELECT status, "assignedHallId" FROM hall_enquiries
           WHERE id = $1 AND "businessId" = $2 FOR UPDATE"#,
    )
    .bind(enquiry_id)
    .bind(business_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Enquiry not found".into()))?;
    let status: String = enq.get("status");
    if !["OWNER_APPROVED", "ASSIGNED", "QUOTE_OFFERED"].contains(&status.as_str()) {
        return Err(AppError::Conflict(
            "Approve the enquiry before assigning a hall".into(),
        ));
    }
    if status == "QUOTE_OFFERED" {
        // Pre-accept reassign: supersede offered quote + release HELD.
        if let Some(qid) = sqlx::query_scalar::<_, Option<Uuid>>(
            r#"SELECT "activeQuoteId" FROM hall_enquiries WHERE id = $1"#,
        )
        .bind(enquiry_id)
        .fetch_one(&mut *tx)
        .await?
        {
            sqlx::query(
                r#"UPDATE event_quotes SET status = 'SUPERSEDED', "supersedeReason" = 'REASSIGN',
                   "updatedAt" = NOW() WHERE id = $1 AND status = 'OFFERED'"#,
            )
            .bind(qid)
            .execute(&mut *tx)
            .await?;
            crate::halls::availability::release_holds_for_quote(&mut *tx, qid).await?;
        }
    }

    let pkg_ok: bool = sqlx::query_scalar(
        r#"SELECT "packageSaved" FROM business_halls
           WHERE id = $1 AND "businessId" = $2 AND "archivedAt" IS NULL"#,
    )
    .bind(body.hall_id)
    .bind(business_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall not found".into()))?;
    if !pkg_ok {
        return Err(AppError::Conflict(
            "Save a package for this hall before assigning enquiries".into(),
        ));
    }
    let package = crate::halls::load_hall_package(&mut *tx, body.hall_id).await?;
    crate::halls::ensure_package_window(package.as_ref(), start)?;

    availability_check(&mut *tx, business_id, Some(body.hall_id), interval, None).await?;

    let hold_hours: i64 = sqlx::query_scalar(
        r#"SELECT COALESCE("assignHoldHours", $2) FROM business_hall_venue WHERE "businessId" = $1"#,
    )
    .bind(business_id)
    .bind(
        std::env::var("HALL_ASSIGN_HOLD_HOURS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(72i32),
    )
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(72) as i64;

    let expires = assign_hold_expires_at(Utc::now(), start, hold_hours);
    // Release prior assignment holds for this enquiry.
    release_holds_for_enquiry(&mut *tx, enquiry_id).await?;

    let hold_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO hall_reservations
           (id, "businessId", "hallId", "enquiryId", "startAt", "endAt", status, "expiresAt")
           VALUES ($1,$2,$3,$4,$5,$6,'HELD',$7)"#,
    )
    .bind(hold_id)
    .bind(business_id)
    .bind(body.hall_id)
    .bind(enquiry_id)
    .bind(start)
    .bind(end)
    .bind(expires)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        r#"UPDATE hall_enquiries SET
           status = 'ASSIGNED',
           "assignedHallId" = $2,
           "proposedStartAt" = $3,
           "proposedEndAt" = $4,
           "activeQuoteId" = NULL,
           "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(enquiry_id)
    .bind(body.hall_id)
    .bind(start)
    .bind(end)
    .execute(&mut *tx)
    .await?;

    write_audit(
        &mut *tx,
        business_id,
        Some(body.hall_id),
        "enquiry",
        &enquiry_id.to_string(),
        "assign",
        uid,
        json!({"holdId": hold_id, "expiresAt": expires}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(body.hall_id)).await?;
    crate::outbox::notify(
        &mut tx,
        enquiry_id,
        uid,
        "Hall assigned",
        "An enquiry was assigned to a hall. Send a quote to the customer.",
        json!({"type": "hall_enquiry_update", "enquiryId": enquiry_id, "hallId": body.hall_id, "status": "ASSIGNED"}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({
        "status": "ASSIGNED",
        "hallId": body.hall_id,
        "holdId": hold_id,
        "expiresAt": expires,
    })))
}
