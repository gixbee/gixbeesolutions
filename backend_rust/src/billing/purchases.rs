use axum::Json;
use hmac::{Hmac, Mac};
use serde_json::{json, Value};
use sha2::Sha256;
use sqlx::Row;
use uuid::Uuid;

use crate::config::is_real_secret;
use crate::error::{AppError, AppResult};
use crate::state::AppState;

const JOBS_PER_PACK: i32 = 3;
const PACK_PRICE_INR: i32 = 49;

pub async fn pack_info(state: &AppState) -> Value {
    let cost = super::get_credits_per_accept(state).await;
    json!({ "credits": i64::from(cost) * i64::from(JOBS_PER_PACK), "jobs": JOBS_PER_PACK,
        "creditsPerAccept": cost, "price": PACK_PRICE_INR, "currency": "INR" })
}

pub async fn create_order(state: &AppState, user_id: &str) -> AppResult<Json<Value>> {
    let pack = pack_info(state).await;
    let credits = pack["credits"].as_i64().unwrap_or(0);
    if credits <= 0 || credits > i64::from(i32::MAX) {
        return Err(AppError::BadRequest("A credit purchase is not available at the current acceptance cost.".into()));
    }
    let mut order = crate::payments::create_razorpay_order(
        state, user_id, "JOB_CREDITS", PACK_PRICE_INR, Some(pack.clone()),
    ).await?;
    order.0["credits"] = pack["credits"].clone();
    Ok(order)
}

fn valid_checkout_signature(secret: &str, order_id: &str, payment_id: &str, signature: &str) -> bool {
    let Ok(bytes) = hex::decode(signature) else { return false; };
    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else { return false; };
    mac.update(format!("{}|{}", order_id, payment_id).as_bytes());
    mac.verify_slice(&bytes).is_ok()
}

pub async fn verify(state: &AppState, user_id: &str, order_id: &str, payment_id: &str, signature: &str) -> AppResult<Value> {
    let key = state.config.razorpay_key_id.as_deref();
    let secret = state.config.razorpay_key_secret.as_deref();
    if !is_real_secret(key) || !is_real_secret(secret) {
        return Err(AppError::ServiceUnavailable("Payment gateway is not configured.".into()));
    }
    if !payment_id.starts_with("pay_") || !payment_id[4..].chars().all(|c| c.is_ascii_alphanumeric()) || payment_id.len() <= 4 {
        return Err(AppError::BadRequest("Invalid payment reference.".into()));
    }
    let uid = Uuid::parse_str(user_id)?;
    let owned: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM payment_orders WHERE "razorpayOrderId" = $1 AND "userId" = $2 AND purpose::text = 'JOB_CREDITS')"#,
    ).bind(order_id).bind(uid).fetch_one(&state.db).await?;
    if !owned { return Err(AppError::Forbidden("This credit order does not belong to you.".into())); }
    if !valid_checkout_signature(secret.unwrap_or(""), order_id, payment_id, signature) {
        return Err(AppError::BadRequest("Invalid payment signature.".into()));
    }
    let response = state.http.get(format!("https://api.razorpay.com/v1/payments/{}", payment_id))
        .basic_auth(key.unwrap_or(""), secret)
        .timeout(std::time::Duration::from_secs(15)).send().await
        .map_err(|_| AppError::ServiceUnavailable("Payment verification is unavailable. Refresh credits after confirmation.".into()))?;
    if !response.status().is_success() {
        return Err(AppError::BadRequest("Could not verify payment. Refresh credits after confirmation.".into()));
    }
    let payment: Value = response.json().await.map_err(|_| AppError::BadRequest("Invalid payment provider response.".into()))?;
    if payment["order_id"].as_str() != Some(order_id) || payment["id"].as_str() != Some(payment_id) {
        return Err(AppError::BadRequest("Payment belongs to a different order.".into()));
    }
    fulfil(state, &payment, Some(uid)).await?
        .ok_or_else(|| AppError::BadRequest("Credit order was not found.".into()))
}

fn validate_capture(payment: &Value, order_id: &str, amount: rust_decimal::Decimal) -> AppResult<()> {
    if payment["id"].as_str().is_none_or(str::is_empty) ||
        payment["order_id"].as_str() != Some(order_id) ||
        payment["status"].as_str() != Some("captured") ||
        payment["currency"].as_str() != Some("INR") ||
        payment["amount"].as_i64().map(rust_decimal::Decimal::from) != Some(amount * rust_decimal::Decimal::from(100)) {
        return Err(AppError::BadRequest("Payment is not captured for this order and amount.".into()));
    }
    Ok(())
}

/// Called after webhook signature validation, or after authenticated API verification.
/// The balance, credit receipt and order status commit together; retries cannot double-credit.
pub async fn fulfil(state: &AppState, payment: &Value, expected_user: Option<Uuid>) -> AppResult<Option<Value>> {
    let Some(order_id) = payment["order_id"].as_str() else { return Ok(None); };
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(r#"SELECT id, "userId", amount, status::text AS status, meta
        FROM payment_orders WHERE "razorpayOrderId" = $1 AND purpose::text = 'JOB_CREDITS' FOR UPDATE"#)
        .bind(order_id).fetch_optional(&mut *tx).await?;
    let Some(row) = row else { return Ok(None); };
    let uid = row.get::<Uuid, _>("userId");
    if expected_user.is_some_and(|u| u != uid) { return Err(AppError::Forbidden("Credit order belongs to another account.".into())); }
    validate_capture(payment, order_id, row.get("amount"))?;
    let meta = row.get::<Option<Value>, _>("meta").unwrap_or(Value::Null);
    let count = meta["credits"].as_i64().filter(|n| *n > 0 && *n <= i64::from(i32::MAX))
        .ok_or_else(|| AppError::BadRequest("Order has no valid credit entitlement. Contact support.".into()))? as i32;
    sqlx::query("SELECT id FROM users WHERE id = $1 FOR UPDATE").bind(uid).fetch_one(&mut *tx).await?;
    let current = sqlx::query_scalar::<_, i32>(r#"SELECT balance FROM job_credits WHERE "userId" = $1 FOR UPDATE"#)
        .bind(uid).fetch_optional(&mut *tx).await?;
    let balance = current.unwrap_or(0);
    if row.get::<String, _>("status") == "CREDITED" { return Ok(Some(json!({ "balance": balance }))); }
    if row.get::<String, _>("status") != "CREATED" { return Err(AppError::BadRequest("Credit order cannot be fulfilled.".into())); }
    let balance = balance.checked_add(count).ok_or_else(|| AppError::BadRequest("Credit balance limit reached.".into()))?;
    if current.is_some() {
        sqlx::query(r#"UPDATE job_credits SET balance = $1, "updatedAt" = NOW() WHERE "userId" = $2"#)
            .bind(balance).bind(uid).execute(&mut *tx).await?;
    } else {
        sqlx::query(r#"INSERT INTO job_credits (id, "userId", balance) VALUES ($1, $2, $3)"#)
            .bind(Uuid::new_v4()).bind(uid).bind(balance).execute(&mut *tx).await?;
    }
    sqlx::query(r#"INSERT INTO credit_transactions (id, "userId", delta, reason, "razorpayPaymentId") VALUES ($1, $2, $3, 'PURCHASE', $4)"#)
        .bind(Uuid::new_v4()).bind(uid).bind(count).bind(payment["id"].as_str()).execute(&mut *tx).await?;
    sqlx::query(r#"UPDATE payment_orders SET status = 'CREDITED', "razorpayPaymentId" = $1, "updatedAt" = NOW() WHERE id = $2"#)
        .bind(payment["id"].as_str()).bind(row.get::<Uuid, _>("id")).execute(&mut *tx).await?;
    tx.commit().await?;
    Ok(Some(json!({ "balance": balance })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn capture_requires_correct_order_amount_currency_and_status() {
        let p = json!({"id":"pay_test", "order_id":"order_test", "amount":4900,"currency":"INR","status":"captured"});
        assert!(validate_capture(&p, "order_test", 49.into()).is_ok());
        for (field, value) in [("order_id", json!("another")), ("amount", json!(1)), ("currency", json!("USD")), ("status", json!("authorized")), ("id", json!(null))] {
            let mut bad = p.clone(); bad[field] = value;
            assert!(validate_capture(&bad, "order_test", 49.into()).is_err());
        }
    }

    #[test]
    fn checkout_signature_is_bound_to_order_and_payment() {
        let mut mac = Hmac::<Sha256>::new_from_slice(b"test-secret").unwrap();
        mac.update(b"order_test|pay_test");
        let signature = hex::encode(mac.finalize().into_bytes());
        assert!(valid_checkout_signature("test-secret", "order_test", "pay_test", &signature));
        assert!(!valid_checkout_signature("test-secret", "order_other", "pay_test", &signature));
        assert!(!valid_checkout_signature("test-secret", "order_test", "pay_other", &signature));
        assert!(!valid_checkout_signature("test-secret", "order_test", "pay_test", "bad"));
    }
}
