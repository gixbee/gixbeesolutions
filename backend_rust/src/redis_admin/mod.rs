use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::AppResult;
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/keys", get(list_keys))
        .route("/key", get(get_key))
}

#[derive(Deserialize)]
struct KeysQuery {
    pattern: Option<String>,
    cursor: Option<String>,
}

async fn list_keys(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<KeysQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "infrastructure")?;
    Ok(Json(json!({
        "pattern": q.pattern.unwrap_or("*".into()),
        "keys": [],
        "redisReady": state.redis.is_ready(),
    })))
}

#[derive(Deserialize)]
struct KeyQuery {
    key: String,
}

async fn get_key(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<KeyQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "infrastructure")?;
    let value = state.redis.get(&q.key).await?;
    Ok(Json(json!({ "key": q.key, "value": value })))
}
