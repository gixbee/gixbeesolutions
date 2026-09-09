use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::AppResult;
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

mod credits;
pub(crate) mod purchases;
pub use credits::{consume_credit, get_credits_per_accept, refund_credit};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/balance", get(get_balance))
        .route("/booking/{booking_id}", get(get_booking_usage))
        .route("/transactions", get(get_transactions))
        .route("/pack-info", get(pack_info))
        .route("/create-order", post(create_order))
        .route("/verify", post(verify_payment))
}

async fn get_balance(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let balance = sqlx::query_scalar::<_, i32>(r#"SELECT balance FROM job_credits WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or(0);
    Ok(Json(json!({ "balance": balance, "creditsPerAccept": get_credits_per_accept(&state).await })))
}

async fn get_booking_usage(
    State(state): State<AppState>,
    user: AuthUser,
    Path(booking_id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let bid = Uuid::parse_str(&booking_id)?;
    let row = sqlx::query(
        r#"SELECT
          COALESCE(SUM(ABS(delta)) FILTER (WHERE reason::text = 'JOB_ACCEPTED'), 0)::bigint AS used,
          COALESCE(SUM(GREATEST(delta, 0)) FILTER (WHERE reason::text IN ('REFUND_CUSTOMER_CANCEL', 'REFUND_NOSHOW')), 0)::bigint AS refunded
          FROM credit_transactions WHERE "userId" = $1 AND "bookingId"::text = $2"#,
    )
    .bind(uid)
    .bind(bid.to_string())
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "creditsUsed": row.get::<i64, _>("used"), "creditsRefunded": row.get::<i64, _>("refunded") })))
}

#[derive(Deserialize)]
struct PageQuery {
    page: Option<String>,
    limit: Option<String>,
}

async fn get_transactions(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let page = q.page.and_then(|s| s.parse::<i64>().ok()).unwrap_or(1).clamp(1, 100000);
    let limit = q.limit.and_then(|s| s.parse::<i64>().ok()).unwrap_or(50).clamp(1, 100);
    let rows = sqlx::query(
        r#"SELECT c.id, c.delta, c.reason::text AS reason, c."bookingId"::text AS "bookingId",
          to_jsonb(c."createdAt") AS "createdAt", b.skill AS "bookingSkill"
          FROM credit_transactions c LEFT JOIN bookings b ON b.id::text = c."bookingId"::text
          WHERE c."userId" = $1 ORDER BY c."createdAt" DESC, c.id DESC LIMIT $2 OFFSET $3"#,
    )
    .bind(uid)
    .bind(limit)
    .bind((page - 1) * limit)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(json!({ "transactions": rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "delta": r.get::<i32, _>("delta"),
        "reason": r.get::<String, _>("reason"),
        "bookingId": r.get::<Option<String>, _>("bookingId"),
        "bookingSkill": r.get::<Option<String>, _>("bookingSkill"),
        "createdAt": r.get::<Value, _>("createdAt"),
    })).collect::<Vec<_>>() })))
}

async fn pack_info(State(state): State<AppState>, _user: AuthUser) -> Json<Value> {
    Json(purchases::pack_info(&state).await)
}

async fn create_order(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    purchases::create_order(&state, &user.user_id).await
}

#[derive(Deserialize)]
struct VerifyBody {
    razorpay_order_id: String,
    razorpay_payment_id: String,
    razorpay_signature: String,
}

async fn verify_payment(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<VerifyBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(purchases::verify(&state, &user.user_id, &body.razorpay_order_id,
        &body.razorpay_payment_id, &body.razorpay_signature).await?))
}
