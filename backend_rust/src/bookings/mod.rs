use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

pub mod cancel;
pub mod progress;
mod ratings;
mod settlement;

pub use cancel::timeout_cancel_booking;

pub async fn rebroadcast_booking(
    state: &AppState,
    booking_id: &str,
) -> AppResult<(bool, usize)> {
    let bid = Uuid::parse_str(booking_id)?;
    let row = sqlx::query(
        r#"SELECT "customerId", "operatorId", skill, "serviceLocation", "serviceLat", "serviceLng",
                  amount, type::text AS type, status::text AS status, description,
                  "arrivalOtp", "completionOtp", "preferredLanguages", "createdAt"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.get::<String, _>("status") != "REQUESTED"
        || row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten().is_some()
        || row.get::<String, _>("type") != "INSTANT"
    {
        return Ok((false, 0));
    }

    crate::jobs::schedule_request_timeout(state.clone(), booking_id.to_string(), 2);

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let skill = row.get::<String, _>("skill");
    let service_lat = row
        .try_get::<Option<rust_decimal::Decimal>, _>("serviceLat")
        .ok()
        .flatten()
        .and_then(|d| d.to_string().parse::<f64>().ok())
        .unwrap_or(0.0);
    let service_lng = row
        .try_get::<Option<rust_decimal::Decimal>, _>("serviceLng")
        .ok()
        .flatten()
        .and_then(|d| d.to_string().parse::<f64>().ok())
        .unwrap_or(0.0);
    let preferred_langs = parse_preferred_languages(
        row.try_get::<Option<String>, _>("preferredLanguages").ok().flatten(),
    );

    let already_notified: std::collections::HashSet<String> =
        get_notified_worker_ids(state, booking_id).await.into_iter().collect();
    let nearby_ids = workers::find_broadcast_target_ids(
        state,
        &customer_id,
        &skill,
        service_lat,
        service_lng,
        &preferred_langs,
        workers::REBROADCAST_RADIUS_STRETCH,
    )
    .await?;
    let fresh_ids: Vec<String> = nearby_ids
        .into_iter()
        .filter(|id| !already_notified.contains(id))
        .collect();

    let search_payload = json!({
        "bookingId": booking_id,
        "id": booking_id,
        "newWorkersNotified": fresh_ids.len(),
    });
    state
        .realtime
        .emit_to_user(&customer_id, "booking_search_expanded", &search_payload)
        .await;
    let body = if fresh_ids.is_empty() {
        "We expanded the search area — still looking for an available pro.".to_string()
    } else {
        format!(
            "We expanded the search area and notified {} more {} pro{}.",
            fresh_ids.len(),
            skill,
            if fresh_ids.len() == 1 { "" } else { "s" }
        )
    };
    state
        .fcm
        .send_to_user(
            state,
            &customer_id,
            "Still searching…",
            &body,
            Some(&[("type", "booking_search_expanded"), ("bookingId", booking_id)]),
        )
        .await;

    if fresh_ids.is_empty() {
        return Ok((true, 0));
    }

    let customer_name: Option<String> = sqlx::query_scalar(
        r#"SELECT split_part(trim(name), ' ', 1) FROM users WHERE id = $1"#,
    )
    .bind(Uuid::parse_str(&customer_id)?)
    .fetch_optional(&state.db)
    .await?
    .flatten();

    let notified_at = chrono::Utc::now().to_rfc3339();
    let arrival_otp = row.get::<Option<String>, _>("arrivalOtp").unwrap_or_default();
    let completion_otp = row.get::<Option<String>, _>("completionOtp").unwrap_or_default();
    let amount = row
        .try_get::<Option<rust_decimal::Decimal>, _>("amount")
        .ok()
        .flatten()
        .map(|d| d.to_string().parse::<f64>().unwrap_or(0.0))
        .unwrap_or(0.0);

    let outbox_payload = json!({
        "bookingId": booking_id,
        "customerId": customer_id,
        "customerName": customer_name,
        "skill": skill,
        "serviceLocation": row.get::<Option<String>, _>("serviceLocation"),
        "serviceLat": service_lat,
        "serviceLng": service_lng,
        "amount": amount,
        "description": row.get::<Option<String>, _>("description"),
        "preferredLanguages": preferred_langs,
        "createdAt": row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("createdAt")
            .ok()
            .flatten()
            .map(|t| t.to_rfc3339())
            .unwrap_or_else(|| notified_at.clone()),
        "notifiedAt": notified_at,
        "arrivalOtp": arrival_otp,
        "completionOtp": completion_otp,
        "notifiedWorkerIds": fresh_ids,
        "attempt": 2,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts) VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.broadcast_created")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&state.db)
    .await?;

    for wid in &fresh_ids {
        let _ = state.redis.add_pending_booking(wid, booking_id).await;
    }

    Ok((true, fresh_ids.len()))
}

fn parse_preferred_languages(raw: Option<String>) -> Vec<String> {
    raw.map(|s| {
        s.split(',')
            .map(|part| part.trim().to_string())
            .filter(|part| !part.is_empty())
            .collect()
    })
    .unwrap_or_default()
}

use cancel::{
    approve_cancel_request, assert_participant, cancel_booking, decline_cancel_request,
    request_cancel, withdraw_cancel_request, CancelOptions,
};
use crate::billing::consume_credit;
use crate::common::money::DEFAULT_BOOKING_PAYMENT_METHOD;
use crate::common::pg::BOOKING_COLS;
use crate::error::{AppError, AppResult};
use crate::jobs;
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;
use crate::workers;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/instant", post(create_instant))
        .route("/my", get(list_my))
        .route("/pending", get(list_pending))
        .route("/me/late-cancel-compensation", get(late_cancel_quote))
        .route("/admin/all", get(admin_list))
        .route("/admin/disputes", get(admin_disputes))
        .route("/admin/disputes/{id}/resolve", patch(admin_resolve_dispute))
        .route("/{id}/accept", patch(accept))
        .route("/{id}/reject", patch(reject))
        .route("/{id}/cancel", patch(cancel))
        .route("/{id}/cancel-request", patch(cancel_request))
        .route("/{id}/cancel-approve", patch(cancel_approve))
        .route("/{id}/cancel-decline", patch(cancel_decline))
        .route("/{id}/cancel-request-withdraw", patch(cancel_withdraw))
        .route("/{id}/arrive", patch(arrive))
        .route("/{id}/arrival", post(arrival_otp))
        .route("/{id}/complete", patch(complete))
        .route("/{id}/completion", post(completion_otp))
        .route("/{id}/refresh-completion-otp", patch(refresh_completion_otp))
        .route("/{id}/mark-paid", patch(mark_paid))
        .route("/{id}/status", get(get_status).patch(update_status))
        .route("/{id}/rating", post(submit_worker_rating))
        .route("/{id}/rate-customer", post(rate_customer))
        .route("/{id}/dispute", post(submit_dispute))
        .route("/{id}", get(get_one))
}

#[derive(Deserialize)]
struct CreateBooking {
    workerId: Option<String>,
    skill: Option<String>,
    serviceLocation: Option<String>,
    serviceLat: Option<f64>,
    serviceLng: Option<f64>,
    scheduledAt: Option<String>,
    amount: Option<f64>,
    r#type: Option<String>,
    addressId: Option<String>,
    paymentMethod: Option<String>,
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateBooking>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let operator_id = body.workerId.as_ref().and_then(|w| Uuid::parse_str(w).ok());
    let booking_type = body.r#type.as_deref().unwrap_or("CUSTOM");
    sqlx::query(
        r#"
        INSERT INTO bookings (id, "customerId", "operatorId", skill, "serviceLocation", "serviceLat", "serviceLng",
            amount, type, status, "paymentMethod", "addressId", "scheduledAt")
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'REQUESTED', $10, $11, COALESCE($12::timestamptz, NOW()))
        "#,
    )
    .bind(id)
    .bind(uid)
    .bind(operator_id)
    .bind(body.skill.as_deref())
    .bind(body.serviceLocation.as_deref())
    .bind(body.serviceLat)
    .bind(body.serviceLng)
    .bind(body.amount)
    .bind(booking_type)
    .bind(body.paymentMethod.as_deref().unwrap_or(DEFAULT_BOOKING_PAYMENT_METHOD))
    .bind(body.addressId.as_deref())
    .bind(body.scheduledAt.as_deref())
    .execute(&state.db)
    .await?;
    get_one(State(state), user, Path(id.to_string())).await
}

#[derive(Deserialize)]
struct OnSiteContact {
    name: String,
    relation: String,
    phone: String,
}

#[derive(Deserialize)]
struct InstantBody {
    skill: String,
    serviceLocation: String,
    serviceLat: f64,
    serviceLng: f64,
    amount: f64,
    description: Option<String>,
    preferredLanguages: Option<Vec<String>>,
    addressId: Option<String>,
    paymentMethod: Option<String>,
    onSiteContact: Option<OnSiteContact>,
}

fn generate_otp() -> String {
    format!("{:04}", rand::random::<u16>() % 9000 + 1000)
}

async fn create_instant(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<InstantBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let blocked = sqlx::query_scalar::<_, bool>(
        r#"SELECT COALESCE("instantHelpBlocked", false) FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .unwrap_or(false);
    if blocked {
        return Err(AppError::Forbidden(
            "Instant Help is blocked on your account".into(),
        ));
    }

    let preferred_langs = body.preferredLanguages.clone().unwrap_or_default();
    let notified_worker_ids = workers::find_broadcast_target_ids(
        &state,
        &user.user_id,
        &body.skill,
        body.serviceLat,
        body.serviceLng,
        &preferred_langs,
        1.0,
    )
    .await?;

    let customer_name: Option<String> = sqlx::query_scalar(
        r#"SELECT split_part(trim(name), ' ', 1) FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .flatten();

    let id = Uuid::new_v4();
    let arrival_otp = generate_otp();
    let completion_otp = generate_otp();
    let notified_at = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        r#"
        INSERT INTO bookings (
            id, "customerId", skill, "serviceLocation", "serviceLat", "serviceLng",
            amount, type, status, description, "paymentMethod", "addressId",
            "arrivalOtp", "completionOtp", "preferredLanguages", "onSiteContact", "scheduledAt"
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'INSTANT', 'REQUESTED', $8, $9, $10, $11, $12, $13, $14, NOW())
        "#,
    )
    .bind(id)
    .bind(uid)
    .bind(&body.skill)
    .bind(&body.serviceLocation)
    .bind(body.serviceLat)
    .bind(body.serviceLng)
    .bind(body.amount)
    .bind(body.description.as_deref())
    .bind(body.paymentMethod.as_deref().unwrap_or(DEFAULT_BOOKING_PAYMENT_METHOD))
    .bind(body.addressId.as_deref())
    .bind(&arrival_otp)
    .bind(&completion_otp)
    .bind(body.preferredLanguages.as_ref().map(|langs| langs.join(",")))
    .bind(
        body.onSiteContact
            .as_ref()
            .map(|c| json!({ "name": c.name, "relation": c.relation, "phone": c.phone })),
    )
    .execute(&state.db)
    .await?;

    let booking_id = id.to_string();
    jobs::schedule_request_timeout(state.clone(), booking_id.clone(), 1);
    let status_patch = json!({
        "status": "REQUESTED",
        "operatorName": null,
        "operatorId": null,
        "customerId": user.user_id,
        "arrivalOtp": arrival_otp,
        "bookingId": booking_id,
        "id": booking_id,
    });
    let _ = state.redis.cache_booking_status(&booking_id, &status_patch).await;
    state
        .realtime
        .emit_to_user(&user.user_id, "booking_status_update", &status_patch)
        .await;
    for wid in &notified_worker_ids {
        let _ = state.redis.add_pending_booking(wid, &booking_id).await;
    }

    let outbox_payload = json!({
        "bookingId": id.to_string(),
        "customerId": user.user_id,
        "customerName": customer_name,
        "skill": body.skill,
        "serviceLocation": body.serviceLocation,
        "serviceLat": body.serviceLat,
        "serviceLng": body.serviceLng,
        "amount": body.amount,
        "description": body.description,
        "preferredLanguages": body.preferredLanguages.clone().unwrap_or_default(),
        "createdAt": notified_at,
        "notifiedAt": notified_at,
        "arrivalOtp": arrival_otp,
        "completionOtp": completion_otp,
        "notifiedWorkerIds": notified_worker_ids,
        "attempt": 1,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts) VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.broadcast_created")
    .bind(id)
    .bind(outbox_payload)
    .execute(&state.db)
    .await?;

    let booking = get_one_inner(&state, &id.to_string()).await?;
    Ok(Json(json!({
        "booking": booking,
        "notified": notified_worker_ids.len(),
    })))
}

async fn list_my(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<Value>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let page = q
        .get("page")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(1)
        .max(1);
    let limit = q
        .get("limit")
        .and_then(|v| v.as_str())
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(50)
        .clamp(1, 100);
    let offset = (page - 1) * limit;

    let statuses: Vec<String> = q
        .get("status")
        .and_then(|v| v.as_str())
        .map(|raw| {
            raw.split(',')
                .map(|s| s.trim().to_uppercase())
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();

    let rows = if statuses.is_empty() {
        sqlx::query(&format!(
            r#"SELECT {BOOKING_COLS} FROM bookings
               WHERE "customerId" = $1 OR "operatorId" = $1
               ORDER BY "scheduledAt" DESC NULLS LAST, "createdAt" DESC, id DESC
               LIMIT $2 OFFSET $3"#
        ))
        .bind(uid)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(&format!(
            r#"SELECT {BOOKING_COLS} FROM bookings
               WHERE ("customerId" = $1 OR "operatorId" = $1) AND status::text = ANY($2)
               ORDER BY "scheduledAt" DESC NULLS LAST, "createdAt" DESC, id DESC
               LIMIT $3 OFFSET $4"#
        ))
        .bind(uid)
        .bind(&statuses)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(rows.iter().map(booking_json).collect()))
}

async fn list_pending(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let worker_id = user.user_id.clone();
    let pending_ids = state.redis.get_pending_booking_ids(&worker_id).await?;

    if !pending_ids.is_empty() {
        let uuids: Vec<Uuid> = pending_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();
        if uuids.is_empty() {
            return Ok(Json(vec![]));
        }

        let rows = sqlx::query(&format!(
            r#"SELECT {BOOKING_COLS} FROM bookings WHERE id = ANY($1)"#
        ))
        .bind(&uuids)
        .fetch_all(&state.db)
        .await?;

        let mut open: Vec<(usize, Value)> = Vec::new();
        for row in rows {
            let id = row.get::<Uuid, _>("id").to_string();
            let status = row.get::<String, _>("status");
            if status == "REQUESTED" {
                let order = pending_ids
                    .iter()
                    .position(|p| p == &id)
                    .unwrap_or(usize::MAX);
                open.push((order, booking_json(&row)));
            } else {
                let _ = state.redis.remove_pending_booking(&worker_id, &id).await;
            }
        }
        open.sort_by_key(|(order, _)| *order);
        return Ok(Json(open.into_iter().map(|(_, v)| v).collect()));
    }

    // Targeted offers already assigned to this worker (operatorId set).
    let uid = Uuid::parse_str(&worker_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {BOOKING_COLS} FROM bookings WHERE "operatorId" = $1 AND status = 'REQUESTED' ORDER BY "createdAt" DESC"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;

    for row in &rows {
        let id = row.get::<Uuid, _>("id").to_string();
        let _ = state.redis.add_pending_booking(&worker_id, &id).await;
    }

    Ok(Json(rows.iter().map(booking_json).collect()))
}

async fn reject(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let worker_id = user.user_id.clone();

    let row = sqlx::query(
        r#"SELECT status::text AS status, "operatorId", "customerId", skill FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let status = row.get::<String, _>("status");
    if status != "REQUESTED" {
        return Err(AppError::BadRequest("Only pending requests can be declined.".into()));
    }

    let operator_id = row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
    let is_assigned = operator_id.map(|u| u.to_string()) == Some(worker_id.clone());
    let pending = state.redis.get_pending_booking_ids(&worker_id).await?;
    let notified = get_notified_worker_ids(&state, &id).await;
    if !is_assigned && !pending.contains(&id) && !notified.contains(&worker_id) {
        return Err(AppError::NotFound("Booking not found".into()));
    }

    let _ = state.redis.remove_pending_booking(&worker_id, &id).await;
    if let Some(skill) = row.get::<Option<String>, _>("skill") {
        if let Some(customer_id) = row.try_get::<Uuid, _>("customerId").ok() {
            let _ = state
                .redis
                .mark_worker_rejected_job(&customer_id.to_string(), &skill, &worker_id)
                .await;
        }
    }

    if is_assigned {
        sqlx::query(r#"UPDATE bookings SET status = 'REJECTED' WHERE id = $1"#)
            .bind(bid)
            .execute(&state.db)
            .await?;
    }

    Ok(Json(json!({ "message": "Booking declined." })))
}

#[derive(Deserialize)]
struct OtpBody {
    otp: String,
}

async fn arrival_otp(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<OtpBody>,
) -> AppResult<Json<Value>> {
    settlement::verify_arrival_otp(&state, &id, &body.otp)
        .await
        .map(Json)
}

async fn completion_otp(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<OtpBody>,
) -> AppResult<Json<Value>> {
    settlement::verify_completion_otp(&state, &id, &body.otp)
        .await
        .map(Json)
}

#[derive(Deserialize)]
struct StatusBody {
    status: String,
}

async fn update_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<StatusBody>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE bookings SET status = $1 WHERE id = $2"#)
        .bind(&body.status)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct RatingBody {
    rating: i32,
}

async fn submit_worker_rating(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<RatingBody>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    ratings::submit_worker_rating(&state, &id, &user.user_id, body.rating)
        .await
        .map(Json)
}

async fn rate_customer(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<RatingBody>,
) -> AppResult<Json<Value>> {
    ratings::rate_customer(&state, &id, &user.user_id, body.rating)
        .await
        .map(Json)
}

#[derive(Deserialize)]
struct DisputeBody {
    reason: String,
}

async fn submit_dispute(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<DisputeBody>,
) -> AppResult<Json<Value>> {
    ratings::report_dispute(&state, &id, &user.user_id, &body.reason)
        .await
        .map(Json)
}

async fn late_cancel_quote(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    cancel::get_late_cancel_compensation_quote(&state, &user.user_id)
        .await
        .map(Json)
}

async fn admin_list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "bookings")?;
    let status = q.get("status").and_then(|v| v.as_str());
    let rows = if let Some(s) = status {
        let statuses: Vec<String> = s
            .split(',')
            .map(|part| part.trim().to_uppercase())
            .filter(|part| !part.is_empty())
            .collect();
        if statuses.is_empty() {
            sqlx::query(&format!(
                r#"SELECT {BOOKING_COLS} FROM bookings ORDER BY "createdAt" DESC LIMIT 50"#
            ))
            .fetch_all(&state.db)
            .await?
        } else {
            sqlx::query(&format!(
                r#"SELECT {BOOKING_COLS} FROM bookings WHERE status::text = ANY($1) ORDER BY "createdAt" DESC LIMIT 50"#
            ))
            .bind(&statuses)
            .fetch_all(&state.db)
            .await?
        }
    } else {
        sqlx::query(&format!(r#"SELECT {BOOKING_COLS} FROM bookings ORDER BY "createdAt" DESC LIMIT 50"#))
            .fetch_all(&state.db)
            .await?
    };
    Ok(Json(json!({ "data": rows.iter().map(booking_json).collect::<Vec<_>>() })))
}

async fn admin_disputes(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ratings::DisputesQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "disputes")?;
    let open_only = q.open.as_deref() == Some("true");
    let page = q
        .page
        .as_deref()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(1)
        .max(1);
    let limit = q
        .limit
        .as_deref()
        .and_then(|s| s.parse::<i64>().ok())
        .unwrap_or(50)
        .clamp(1, 100);
    let data = ratings::list_disputes(&state, open_only, page, limit).await?;
    Ok(Json(json!(data)))
}

#[derive(Deserialize)]
struct ResolveDisputeBody {
    resolution: String,
}

async fn admin_resolve_dispute(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ResolveDisputeBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "disputes")?;
    ratings::resolve_dispute(&state, &id, &body.resolution)
        .await
        .map(Json)
}

async fn get_one(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    Ok(Json(get_one_inner(&state, &id).await?))
}

async fn get_one_inner(state: &AppState, id: &str) -> AppResult<Value> {
    let bid = Uuid::parse_str(id)?;
    let row = sqlx::query(&format!(r#"SELECT {BOOKING_COLS} FROM bookings WHERE id = $1"#))
        .bind(bid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    Ok(booking_json(&row))
}

async fn get_notified_worker_ids(state: &AppState, booking_id: &str) -> Vec<String> {
    let raw = state
        .redis
        .get(&format!("booking:notified:{}", booking_id))
        .await
        .ok()
        .flatten();
    match raw {
        Some(s) => serde_json::from_str(&s).unwrap_or_default(),
        None => vec![],
    }
}

fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let r = 6371.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lng = (lng2 - lng1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    r * c
}

async fn publish_accepted_status(
    state: &AppState,
    booking_id: &str,
    customer_id: &str,
    worker_id: &str,
    operator_name: Option<&str>,
    arrival_otp: Option<&str>,
) {
    let status_patch = json!({
        "status": "ACCEPTED",
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": worker_id,
        "customerId": customer_id,
        "operatorName": operator_name,
        "arrivalOtp": arrival_otp,
    });
    let _ = state.redis.cache_booking_status(booking_id, &status_patch).await;
    let customer_payload = json!({
        "status": "ACCEPTED",
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": worker_id,
        "customerId": customer_id,
        "operatorName": operator_name,
        "arrivalOtp": arrival_otp,
    });
    state
        .realtime
        .emit_to_user(customer_id, "booking_status_update", &customer_payload)
        .await;
    let worker_payload = json!({
        "status": "ACCEPTED",
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": worker_id,
        "customerId": customer_id,
        "operatorName": operator_name,
        "arrivalOtp": null,
    });
    state
        .realtime
        .emit_to_user(worker_id, "booking_status_update", &worker_payload)
        .await;
}

async fn accept_response(
    state: &AppState,
    bid: Uuid,
    worker_id: &str,
    operator_name: Option<String>,
) -> AppResult<Json<Value>> {
    let row = sqlx::query(&format!(r#"SELECT {BOOKING_COLS} FROM bookings WHERE id = $1"#))
        .bind(bid)
        .fetch_one(&state.db)
        .await?;
    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    Ok(Json(json!({
        "message": "Booking accepted. Head to the service location now.",
        "status": "ACCEPTED",
        "booking": {
            "id": bid.to_string(),
            "status": "ACCEPTED",
            "skill": row.get::<Option<String>, _>("skill"),
            "amount": row.get::<Option<rust_decimal::Decimal>, _>("amount"),
            "serviceLocation": row.get::<Option<String>, _>("serviceLocation"),
            "serviceLat": row.try_get::<Option<rust_decimal::Decimal>, _>("serviceLat").ok().flatten(),
            "serviceLng": row.try_get::<Option<rust_decimal::Decimal>, _>("serviceLng").ok().flatten(),
            "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
            "customer": { "id": customer_id },
            "operator": { "id": worker_id, "name": operator_name },
        },
    })))
}

async fn accept(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let worker_id = Uuid::parse_str(&user.user_id)?;
    let worker_id_str = user.user_id.clone();

    let mut tx = state.db.begin().await?;

    let locked = sqlx::query(
        r#"SELECT id, status::text AS status, "operatorId", "customerId", skill, amount,
                  "serviceLocation", "serviceLat", "serviceLng", "arrivalOtp", type::text AS type,
                  "createdAt"
           FROM bookings WHERE id = $1 FOR UPDATE"#,
    )
    .bind(bid)
    .fetch_optional(&mut *tx)
    .await?;

    let locked = locked.ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    let status = locked.get::<String, _>("status");

    if status != "REQUESTED" {
        if status == "ACCEPTED" {
            let op = locked.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
            if op == Some(worker_id) {
                tx.rollback().await?;
                let operator_name: Option<String> = sqlx::query_scalar(
                    r#"SELECT name FROM users WHERE id = $1"#,
                )
                .bind(worker_id)
                .fetch_optional(&state.db)
                .await?;
                return accept_response(&state, bid, &worker_id_str, operator_name).await;
            }
        }
        tx.rollback().await?;
        return Err(AppError::BadRequest(
            "This booking is no longer available — it may have been accepted or cancelled.".into(),
        ));
    }

    let existing_operator = locked.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
    if existing_operator.is_none() {
        let pending = state
            .redis
            .get_pending_booking_ids(&worker_id_str)
            .await
            .unwrap_or_default();
        let notified = get_notified_worker_ids(&state, &id).await;
        if !pending.contains(&id) && !notified.contains(&worker_id_str) {
            tx.rollback().await?;
            return Err(AppError::BadRequest(
                "You are not eligible to accept this booking.".into(),
            ));
        }
    } else if existing_operator != Some(worker_id) {
        tx.rollback().await?;
        return Err(AppError::BadRequest("You are not assigned to this booking.".into()));
    }

    let remaining = consume_credit(&state, &mut tx, worker_id, bid).await?;
    let force_offline = remaining == 0;

    let customer_id = locked.get::<Uuid, _>("customerId");
    let arrival_otp = locked
        .try_get::<Option<String>, _>("arrivalOtp")
        .ok()
        .flatten();

    let (accept_lat, accept_lng, accept_distance_km) =
        if let Some((lat, lng)) = state.redis.get_worker_location(&worker_id_str).await? {
            let job_lat = locked
                .try_get::<Option<rust_decimal::Decimal>, _>("serviceLat")
                .ok()
                .flatten()
                .and_then(|d| d.to_string().parse::<f64>().ok());
            let job_lng = locked
                .try_get::<Option<rust_decimal::Decimal>, _>("serviceLng")
                .ok()
                .flatten()
                .and_then(|d| d.to_string().parse::<f64>().ok());
            let dist = match (job_lat, job_lng) {
                (Some(jlat), Some(jlng)) => {
                    Some((haversine_km(lat, lng, jlat, jlng) * 100.0).round() / 100.0)
                }
                _ => None,
            };
            (Some(lat), Some(lng), dist)
        } else {
            (None, None, None)
        };

    sqlx::query(
        r#"UPDATE bookings
           SET status = 'ACCEPTED',
               "operatorId" = $1,
               "acceptedAt" = NOW(),
               "acceptLat" = $2,
               "acceptLng" = $3,
               "acceptDistanceKm" = $4
           WHERE id = $5"#,
    )
    .bind(worker_id)
    .bind(accept_lat)
    .bind(accept_lng)
    .bind(accept_distance_km)
    .bind(bid)
    .execute(&mut *tx)
    .await?;

    let other_pending = sqlx::query(
        r#"SELECT id, "customerId" FROM bookings
           WHERE "operatorId" = $1 AND status = 'REQUESTED' AND id != $2"#,
    )
    .bind(worker_id)
    .bind(bid)
    .fetch_all(&mut *tx)
    .await?;

    let cancelled_booking_ids: Vec<String> = other_pending
        .iter()
        .map(|r| r.get::<Uuid, _>("id").to_string())
        .collect();
    let cancelled_customer_ids: Vec<String> = other_pending
        .iter()
        .filter_map(|r| r.try_get::<Uuid, _>("customerId").ok().map(|u| u.to_string()))
        .collect();

    if !cancelled_booking_ids.is_empty() {
        sqlx::query(
            r#"UPDATE bookings SET status = 'CANCELLED'
               WHERE "operatorId" = $1 AND status = 'REQUESTED' AND id != $2"#,
        )
        .bind(worker_id)
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    }

    let operator_name: Option<String> = sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
        .bind(worker_id)
        .fetch_optional(&mut *tx)
        .await?;

    let outbox_payload = json!({
        "bookingId": id,
        "workerId": worker_id_str,
        "customerId": customer_id.to_string(),
        "operatorName": operator_name,
        "arrivalOtp": arrival_otp,
        "cancelledBookingIds": cancelled_booking_ids,
        "cancelledCustomerIds": cancelled_customer_ids,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts)
           VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.accepted")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    publish_accepted_status(
        &state,
        &id,
        &customer_id.to_string(),
        &worker_id_str,
        operator_name.as_deref(),
        arrival_otp.as_deref(),
    )
    .await;
    workers::set_worker_status(&state, &worker_id_str, "busy").await;

    if force_offline {
        let _ = workers::force_offline(&state, &worker_id_str).await;
        state
            .fcm
            .send_to_user(
                &state,
                &worker_id_str,
                "Out of credits",
                "You have been taken offline because you have no job credits left. Buy a pack to receive new jobs.",
                Some(&[("type", "out_of_credits")]),
            )
            .await;
    }

    accept_response(&state, bid, &worker_id_str, operator_name).await
}

#[derive(Deserialize)]
struct CancelBody {
    reason: Option<String>,
}

async fn cancel(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<CancelBody>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    let reason = body.reason.as_deref().unwrap_or("Not specified");
    let source = if user.role.as_deref() == Some("CUSTOMER") {
        "customer"
    } else {
        "operator"
    };
    let opts = if source == "operator" {
        CancelOptions {
            apply_late_cancel_strike: false,
            skip_stage_gate: true,
            refund_job_credit: true,
        }
    } else {
        CancelOptions::default()
    };
    cancel_booking(&state, &id, reason, source, opts).await.map(Json)
}

async fn cancel_request(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<CancelBody>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    request_cancel(&state, &id, &user.user_id, body.reason.as_deref())
        .await
        .map(Json)
}

async fn cancel_approve(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    approve_cancel_request(&state, &id, &user.user_id).await.map(Json)
}

async fn cancel_decline(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    decline_cancel_request(&state, &id, &user.user_id).await.map(Json)
}

async fn cancel_withdraw(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    withdraw_cancel_request(&state, &id, &user.user_id).await.map(Json)
}

async fn arrive(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    settlement::notify_arrival(&state, &id, &user.user_id)
        .await
        .map(Json)
}

async fn complete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    settlement::notify_completion(&state, &id, &user.user_id)
        .await
        .map(Json)
}

async fn refresh_completion_otp(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_participant(&state, &id, &user.user_id).await?;
    settlement::refresh_completion_otp(&state, &id, &user.user_id)
        .await
        .map(Json)
}

#[derive(Deserialize, Default)]
struct MarkPaidBody {
    collectionMethod: Option<String>,
    honestyCheck: Option<String>,
    safetyCheck: Option<String>,
}

async fn mark_paid(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<MarkPaidBody>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "customerId", "operatorId", "isPaid",
                  "workerPaidConfirmed", "customerPaidConfirmed"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let customer_id = row.get::<Uuid, _>("customerId");
    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();
    let is_worker = operator_id == Some(uid);
    let is_customer = customer_id == uid;
    if !is_worker && !is_customer {
        return Err(AppError::BadRequest(
            "Only participants of this booking can mark it paid".into(),
        ));
    }
    if row.get::<String, _>("status") != "COMPLETED" {
        return Err(AppError::BadRequest(
            "Only completed bookings can be marked paid".into(),
        ));
    }

    let mut worker_confirmed = row.get::<bool, _>("workerPaidConfirmed");
    let mut customer_confirmed = row.get::<bool, _>("customerPaidConfirmed");
    let mut is_paid = row.get::<bool, _>("isPaid");

    if is_worker {
        worker_confirmed = true;
    }
    if is_customer {
        customer_confirmed = true;
    }

    let both_confirmed = worker_confirmed && customer_confirmed;
    let other_missing = is_customer && operator_id.is_none();

    if both_confirmed || other_missing || is_paid {
        is_paid = true;
    }

    sqlx::query(
        r#"UPDATE bookings SET
            "isPaid" = $1,
            "workerPaidConfirmed" = $2,
            "customerPaidConfirmed" = $3,
            "workerHonestyCheck" = COALESCE($4, "workerHonestyCheck"),
            "paymentCollectionMethod" = COALESCE($5, "paymentCollectionMethod"),
            "customerSafetyCheck" = COALESCE($6, "customerSafetyCheck")
           WHERE id = $7"#,
    )
    .bind(is_paid)
    .bind(worker_confirmed)
    .bind(customer_confirmed)
    .bind(body.honestyCheck.as_deref())
    .bind(body.collectionMethod.as_deref())
    .bind(body.safetyCheck.as_deref())
    .bind(bid)
    .execute(&state.db)
    .await?;

    let operator_name: Option<String> = if let Some(op) = operator_id {
        sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
            .bind(op)
            .fetch_optional(&state.db)
            .await?
    } else {
        None
    };

    let outbox_payload = json!({
        "bookingId": id,
        "customerId": customer_id.to_string(),
        "operatorId": operator_id.map(|u| u.to_string()),
        "operatorName": operator_name,
        "status": "COMPLETED",
        "isPaid": is_paid,
        "workerPaidConfirmed": worker_confirmed,
        "customerPaidConfirmed": customer_confirmed,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts) VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.payment_confirmed")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&state.db)
    .await?;

    let status_patch = json!({
        "status": "COMPLETED",
        "bookingId": id,
        "id": id,
        "operatorId": operator_id.map(|u| u.to_string()),
        "customerId": customer_id.to_string(),
        "operatorName": operator_name,
        "isPaid": is_paid,
        "workerPaidConfirmed": worker_confirmed,
        "customerPaidConfirmed": customer_confirmed,
    });
    let _ = state.redis.cache_booking_status(&id, &status_patch).await;
    if let Some(cid) = Some(customer_id.to_string()) {
        state
            .realtime
            .emit_to_user(&cid, "booking_status_update", &status_patch)
            .await;
    }
    if let Some(oid) = operator_id.map(|u| u.to_string()) {
        state
            .realtime
            .emit_to_user(&oid, "booking_status_update", &status_patch)
            .await;
    }

    Ok(Json(json!({
        "message": if is_paid {
            "Booking marked as paid."
        } else {
            "Payment confirmation recorded. Waiting for the other party."
        },
        "isPaid": is_paid,
        "workerPaidConfirmed": worker_confirmed,
        "customerPaidConfirmed": customer_confirmed,
    })))
}

async fn get_status(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let mut payload = if let Some(v) = state.redis.get(&format!("booking:status:{id}")).await? {
        serde_json::from_str(&v).unwrap_or(json!({}))
    } else {
        get_one_inner(&state, &id).await?
    };

    // Payment flags always come from DB — Redis cache can lag behind mark-paid.
    if let Some(row) = sqlx::query(
        r#"SELECT status::text AS status, "isPaid", "workerPaidConfirmed", "customerPaidConfirmed"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    {
        if let Some(obj) = payload.as_object_mut() {
            obj.insert("status".into(), json!(row.get::<String, _>("status")));
            obj.insert("isPaid".into(), json!(row.get::<bool, _>("isPaid")));
            obj.insert(
                "workerPaidConfirmed".into(),
                json!(row.get::<bool, _>("workerPaidConfirmed")),
            );
            obj.insert(
                "customerPaidConfirmed".into(),
                json!(row.get::<bool, _>("customerPaidConfirmed")),
            );
            obj.insert("bookingId".into(), json!(id));
            obj.insert("id".into(), json!(id));
        }
    }

    Ok(Json(payload))
}

fn booking_json(row: &sqlx::postgres::PgRow) -> Value {
    let id = row.get::<Uuid, _>("id").to_string();
    json!({
        "id": id,
        "bookingId": id,
        "customerId": row.get::<Uuid, _>("customerId").to_string(),
        "operatorId": row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten().map(|u| u.to_string()),
        "skill": row.get::<Option<String>, _>("skill"),
        "serviceLocation": row.get::<Option<String>, _>("serviceLocation"),
        "serviceLat": row.try_get::<Option<rust_decimal::Decimal>, _>("serviceLat").ok().flatten().map(|d| d.to_string().parse::<f64>().unwrap_or(0.0)),
        "serviceLng": row.try_get::<Option<rust_decimal::Decimal>, _>("serviceLng").ok().flatten().map(|d| d.to_string().parse::<f64>().unwrap_or(0.0)),
        "totalAmount": row.get::<Option<rust_decimal::Decimal>, _>("amount"),
        "amount": row.get::<Option<rust_decimal::Decimal>, _>("amount"),
        "type": row.get::<String, _>("type"),
        "status": row.get::<String, _>("status"),
        "paymentMethod": row.get::<Option<String>, _>("paymentMethod"),
        "description": row.get::<Option<String>, _>("description"),
        "isPaid": row.try_get::<bool, _>("isPaid").ok().unwrap_or(false),
        "workerPaidConfirmed": row.try_get::<bool, _>("workerPaidConfirmed").ok().unwrap_or(false),
        "customerPaidConfirmed": row.try_get::<bool, _>("customerPaidConfirmed").ok().unwrap_or(false),
        "paymentCollectionMethod": row.try_get::<Option<String>, _>("paymentCollectionMethod").ok().flatten(),
        "workerHonestyCheck": row.try_get::<Option<String>, _>("workerHonestyCheck").ok().flatten(),
        "customerSafetyCheck": row.try_get::<Option<String>, _>("customerSafetyCheck").ok().flatten(),
        "scheduledAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("scheduledAt").ok(),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "completedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("completedAt").ok(),
        "acceptedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("acceptedAt").ok(),
    })
}
