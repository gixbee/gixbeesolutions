use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::common::money::WALLET_PAYMENTS_ENABLED;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

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
