use axum::{
    body::Bytes,
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::Sha256;
use sqlx::Row;
use uuid::Uuid;

use crate::common::money::WALLET_PAYMENTS_ENABLED;
use crate::config::is_real_secret;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

type HmacSha256 = Hmac<Sha256>;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/gateway-status", get(gateway_status))
        .route("/recharge/order", post(create_recharge_order))
        .route("/period-fee/order", post(create_period_fee_order))
        .route("/late-cancel-compensation/order", post(create_late_cancel_order))
        .route("/hiring-match/order", post(create_hiring_match_order))
        .route("/extra-job-type/order", post(create_extra_job_type_order))
        .route("/webhook", post(webhook))
}

async fn gateway_status(State(state): State<AppState>) -> Json<Value> {
    let configured = is_real_secret(state.config.razorpay_key_id.as_deref())
        && is_real_secret(state.config.razorpay_key_secret.as_deref());
    Json(json!({
        "wallet": {
            "available": WALLET_PAYMENTS_ENABLED,
            "message": if WALLET_PAYMENTS_ENABLED { serde_json::Value::Null } else { json!("Gixbee Wallet is off — pay the pro directly (cash/UPI).") }
        },
        "cash": { "available": true },
        "razorpay": {
            "available": configured,
            "needsApiKey": !configured,
            "message": if configured { serde_json::Value::Null } else { json!("Razorpay not configured — set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET") }
        },
        "upi": {
            "available": false,
            "provider": "PHONEPE",
            "needsApiKey": true,
            "message": "In-app UPI gateway not configured — use cash/UPI with the pro, or Razorpay for period fee / late-cancel."
        }
    }))
}

#[derive(Deserialize)]
struct AmountBody {
    amount: Option<f64>,
}

async fn create_recharge_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<AmountBody>,
) -> AppResult<Json<Value>> {
    if !WALLET_PAYMENTS_ENABLED {
        return Err(AppError::BadRequest(
            "Wallet payments are disabled".into(),
        ));
    }
    create_razorpay_order(&state, &user.user_id, "WALLET_RECHARGE", body.amount.unwrap_or(100.0)).await
}

async fn create_period_fee_order(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    create_razorpay_order(&state, &user.user_id, "PERIOD_FEE", 99.0).await
}

async fn create_late_cancel_order(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    create_razorpay_order(&state, &user.user_id, "LATE_CANCEL_COMPENSATION", 50.0).await
}

async fn create_hiring_match_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(_body): Json<Value>,
) -> AppResult<Json<Value>> {
    create_razorpay_order(&state, &user.user_id, "HIRING_MATCH", 49.0).await
}

async fn create_extra_job_type_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(_body): Json<Value>,
) -> AppResult<Json<Value>> {
    create_razorpay_order(&state, &user.user_id, "EXTRA_JOB_TYPE", 50.0).await
}

async fn create_razorpay_order(
    state: &AppState,
    user_id: &str,
    purpose: &str,
    amount_inr: f64,
) -> AppResult<Json<Value>> {
    if !is_real_secret(state.config.razorpay_key_id.as_deref()) {
        return Err(AppError::ServiceUnavailable("Payment gateway not configured".into()));
    }
    let order_id = format!("order_{}", Uuid::new_v4());
    let id = Uuid::new_v4();
    let uid = Uuid::parse_str(user_id)?;
    let amount_paise = (amount_inr * 100.0) as i64;
    sqlx::query(
        r#"INSERT INTO payment_orders (id, "userId", purpose, amount, status, "razorpayOrderId") VALUES ($1, $2, $3, $4, 'CREATED', $5)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(purpose)
    .bind(amount_inr)
    .bind(&order_id)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({
        "orderId": id.to_string(),
        "razorpayOrderId": order_id,
        "amount": amount_paise,
        "currency": "INR",
        "key": state.config.razorpay_key_id,
    })))
}

async fn webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<StatusCode, StatusCode> {
    let signature = headers
        .get("x-razorpay-signature")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if let Some(secret) = &state.config.razorpay_webhook_secret {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        mac.update(&body);
        let expected = hex::encode(mac.finalize().into_bytes());
        if signature != expected {
            return Err(StatusCode::FORBIDDEN);
        }
    }
    let payload: Value = serde_json::from_slice(&body).map_err(|_| StatusCode::BAD_REQUEST)?;
    if let Some(order_id) = payload
        .pointer("/payload/payment/entity/order_id")
        .and_then(|v| v.as_str())
    {
        sqlx::query(
            r#"UPDATE payment_orders SET status = 'CREDITED' WHERE "razorpayOrderId" = $1 AND status = 'CREATED'"#,
        )
        .bind(order_id)
        .execute(&state.db)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    }
    Ok(StatusCode::OK)
}
