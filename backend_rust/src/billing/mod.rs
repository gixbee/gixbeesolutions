use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

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
    Ok(Json(json!({ "balance": balance, "creditsPerAccept": 15 })))
}

async fn get_booking_usage(
    State(state): State<AppState>,
    user: AuthUser,
    Path(booking_id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let bid = Uuid::parse_str(&booking_id)?;
    let row = sqlx::query(
        r#"SELECT * FROM credit_transactions WHERE "userId" = $1 AND "bookingId" = $2"#,
    )
    .bind(uid)
    .bind(bid)
    .fetch_optional(&state.db)
    .await?;
    Ok(Json(row.map(|r| json!({
        "amount": r.get::<i32, _>("amount"),
        "reason": r.get::<String, _>("reason"),
    })).unwrap_or(json!({ "amount": 0 }))))
}

#[derive(Deserialize)]
struct PageQuery {
    page: Option<String>,
    limit: Option<String>,
}

async fn get_transactions(
    State(state): State<AppState>,
    user: AuthUser,
    Query(_q): Query<PageQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"SELECT * FROM credit_transactions WHERE "userId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "amount": r.get::<i32, _>("amount"),
        "reason": r.get::<String, _>("reason"),
    })).collect()))
}

async fn pack_info() -> Json<Value> {
    Json(json!({ "credits": 30, "price": 299, "currency": "INR" }))
}

async fn create_order(State(state): State<AppState>, _user: AuthUser) -> AppResult<Json<Value>> {
    Ok(Json(json!({
        "orderId": Uuid::new_v4().to_string(),
        "amount": 29900,
        "currency": "INR",
        "keyId": state.config.razorpay_key_id,
    })))
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
    Json(_body): Json<VerifyBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let balance = sqlx::query_scalar::<_, i32>(r#"SELECT balance FROM job_credits WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or(0);
    Ok(Json(json!({ "balance": balance })))
}
