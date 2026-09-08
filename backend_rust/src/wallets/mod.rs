use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::money::WALLET_PAYMENTS_ENABLED;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub async fn add_funds(state: &AppState, user_id: &str, amount_inr: i32, description: &str) -> AppResult<()> {
    if amount_inr <= 0 {
        return Ok(());
    }
    let uid = Uuid::parse_str(user_id)?;
    let amount = Decimal::from(amount_inr);
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE users SET "walletBalance" = "walletBalance" + $1 WHERE id = $2"#,
    )
    .bind(amount)
    .bind(uid)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"INSERT INTO wallet_transactions (id, "userId", amount, type, description)
           VALUES ($1, $2, $3, 'CREDIT', $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(uid)
    .bind(amount)
    .bind(description)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/balance", get(get_balance))
        .route("/transactions", get(get_transactions))
}

async fn get_balance(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    if !WALLET_PAYMENTS_ENABLED {
        return Ok(Json(json!({ "enabled": false, "balance": 0 })));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    let balance = sqlx::query_scalar::<_, rust_decimal::Decimal>(
        r#"SELECT "walletBalance" FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "enabled": true, "balance": balance })))
}

async fn get_transactions(
    State(state): State<AppState>,
    user: AuthUser,
    Query(_q): Query<Value>,
) -> AppResult<Json<Vec<Value>>> {
    if !WALLET_PAYMENTS_ENABLED {
        return Ok(Json(vec![]));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"SELECT * FROM wallet_transactions WHERE "userId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "amount": r.get::<rust_decimal::Decimal, _>("amount"),
        "type": r.get::<String, _>("type"),
        "description": r.get::<String, _>("description"),
    })).collect()))
}
