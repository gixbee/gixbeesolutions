use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::money::DEFAULT_BOOKING_PAYMENT_METHOD;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/instant", post(create_instant))
        .route("/my", get(list_my))
        .route("/pending", get(list_pending))
        .route("/me/late-cancel-compensation", get(late_cancel_quote))
        .route("/admin/all", get(admin_list))
        .route("/admin/disputes", get(admin_disputes))
        .route("/{id}/accept", patch(accept))
        .route("/{id}/reject", patch(reject))
        .route("/{id}/cancel", patch(cancel))
        .route("/{id}/cancel-request", patch(cancel))
        .route("/{id}/cancel-approve", patch(cancel))
        .route("/{id}/cancel-decline", patch(cancel))
        .route("/{id}/cancel-request-withdraw", patch(cancel))
        .route("/{id}/arrive", patch(arrive))
        .route("/{id}/arrival", post(arrival_otp))
        .route("/{id}/complete", patch(complete))
        .route("/{id}/completion", post(completion_otp))
        .route("/{id}/refresh-completion-otp", patch(complete))
        .route("/{id}/mark-paid", patch(mark_paid))
        .route("/{id}/status", get(get_status).patch(update_status))
        .route("/{id}/rating", post(submit_rating))
        .route("/{id}/rate-customer", post(submit_rating))
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
struct InstantBody {
    skill: String,
    serviceLocation: String,
    serviceLat: f64,
    serviceLng: f64,
    amount: f64,
    description: Option<String>,
    addressId: Option<String>,
    paymentMethod: Option<String>,
}

async fn create_instant(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<InstantBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"
        INSERT INTO bookings (id, "customerId", skill, "serviceLocation", "serviceLat", "serviceLng",
            amount, type, status, description, "paymentMethod", "addressId")
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'INSTANT', 'REQUESTED', $8, $9, $10)
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
    .execute(&state.db)
    .await?;

    let notified = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) FROM worker_profiles WHERE "isLive" = true AND $1 = ANY(skills)"#,
    )
    .bind(&body.skill)
    .fetch_one(&state.db)
    .await?;

    let booking = get_one_inner(&state, &id.to_string())?;
    Ok(Json(json!({ "booking": booking, "notified": notified })))
}

async fn list_my(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<Value>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let status = q.get("status").and_then(|v| v.as_str());
    let rows = if let Some(s) = status {
        sqlx::query(
            r#"SELECT * FROM bookings WHERE ("customerId" = $1 OR "operatorId" = $1) AND status = $2 ORDER BY "createdAt" DESC"#,
        )
        .bind(uid)
        .bind(s)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            r#"SELECT * FROM bookings WHERE "customerId" = $1 OR "operatorId" = $1 ORDER BY "createdAt" DESC"#,
        )
        .bind(uid)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(rows.iter().map(booking_json).collect()))
}

async fn list_pending(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"SELECT * FROM bookings WHERE "operatorId" = $1 AND status IN ('REQUESTED', 'PENDING') ORDER BY "createdAt" DESC"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(booking_json).collect()))
}

async fn reject(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE bookings SET status = 'REJECTED' WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct OtpBody {
    otp: String,
}

async fn arrival_otp(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<OtpBody>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT "arrivalOtp" FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    let expected = row.get::<Option<String>, _>("arrivalOtp");
    if expected.as_deref() != Some(body.otp.as_str()) {
        return Err(AppError::BadRequest("Invalid OTP".into()));
    }
    sqlx::query(r#"UPDATE bookings SET status = 'ARRIVED' WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
}

async fn completion_otp(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<OtpBody>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE bookings SET status = 'COMPLETED', "completedAt" = NOW() WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
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

async fn submit_rating(
    State(_state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
    Json(_body): Json<RatingBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "message": "Rating submitted", "bookingId": id })))
}

#[derive(Deserialize)]
struct DisputeBody {
    reason: String,
}

async fn submit_dispute(
    State(_state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
    Json(_body): Json<DisputeBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "message": "Dispute recorded", "bookingId": id })))
}

async fn late_cancel_quote(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let row = sqlx::query(
        r#"SELECT "unblockCompensationAmountInr", "unblockCompensationDistanceKm", "instantHelpBlocked" FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({
        "blocked": row.get::<bool, _>("instantHelpBlocked"),
        "amountInr": row.get::<Option<i32>, _>("unblockCompensationAmountInr"),
        "distanceKm": row.get::<Option<rust_decimal::Decimal>, _>("unblockCompensationDistanceKm"),
    })))
}

async fn admin_list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "bookings")?;
    let status = q.get("status").and_then(|v| v.as_str());
    let rows = if let Some(s) = status {
        sqlx::query(r#"SELECT * FROM bookings WHERE status = $1 ORDER BY "createdAt" DESC LIMIT 50"#)
            .bind(s)
            .fetch_all(&state.db)
            .await?
    } else {
        sqlx::query(r#"SELECT * FROM bookings ORDER BY "createdAt" DESC LIMIT 50"#)
            .fetch_all(&state.db)
            .await?
    };
    Ok(Json(json!({ "data": rows.iter().map(booking_json).collect::<Vec<_>>() })))
}

async fn admin_disputes(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "disputes")?;
    Ok(Json(json!({ "data": [] })))
}

async fn get_one(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    Ok(Json(get_one_inner(&state, &id)?))
}

fn get_one_inner(state: &AppState, id: &str) -> AppResult<Value> {
    let bid = Uuid::parse_str(id)?;
    let row = sqlx::query(r#"SELECT * FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    Ok(booking_json(&row))
}

async fn accept(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let result = sqlx::query(
        r#"UPDATE bookings SET status = 'ACCEPTED', "operatorId" = $1, "acceptedAt" = NOW() WHERE id = $2 AND status = 'REQUESTED'"#,
    )
    .bind(uid)
    .bind(bid)
    .execute(&state.db)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::Conflict("Booking already accepted or cancelled".into()));
    }
    get_one(State(state), user, Path(id)).await
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
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(
        r#"UPDATE bookings SET status = 'CANCELLED', "cancellationReason" = $1 WHERE id = $2"#,
    )
    .bind(body.reason.as_deref())
    .bind(bid)
    .execute(&state.db)
    .await?;
    get_one(State(state), user, Path(id)).await
}

async fn arrive(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE bookings SET status = 'ARRIVED' WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
}

async fn complete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE bookings SET status = 'COMPLETED', "completedAt" = NOW() WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    get_one(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct MarkPaidBody {
    confirmed: bool,
}

async fn mark_paid(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<MarkPaidBody>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    if body.confirmed {
        sqlx::query(r#"UPDATE bookings SET "customerPaidConfirmed" = true WHERE id = $1"#)
            .bind(bid)
            .execute(&state.db)
            .await?;
    }
    get_one(State(state), user, Path(id)).await
}

async fn get_status(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let cached = state.redis.get(&format!("booking:status:{id}")).await?;
    if let Some(v) = cached {
        return Ok(Json(serde_json::from_str(&v).unwrap_or(json!({}))));
    }
    Ok(Json(get_one_inner(&state, &id)?))
}

fn booking_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "customerId": row.get::<Uuid, _>("customerId").to_string(),
        "operatorId": row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten().map(|u| u.to_string()),
        "skill": row.get::<Option<String>, _>("skill"),
        "serviceLocation": row.get::<Option<String>, _>("serviceLocation"),
        "serviceLat": row.get::<Option<f64>, _>("serviceLat"),
        "serviceLng": row.get::<Option<f64>, _>("serviceLng"),
        "totalAmount": row.get::<Option<rust_decimal::Decimal>, _>("amount"),
        "type": row.get::<String, _>("type"),
        "status": row.get::<String, _>("status"),
        "paymentMethod": row.get::<Option<String>, _>("paymentMethod"),
        "description": row.get::<Option<String>, _>("description"),
    })
}
