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
        .route("/admin/current", get(current))
        .route("/admin/history", get(history))
        .route("/admin/traffic", get(traffic))
}

#[derive(Deserialize)]
struct MinutesQuery {
    minutes: Option<String>,
}

async fn current(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "monitoring")?;
    Ok(Json(json!({
        "redis": { "ready": state.redis.is_ready() },
        "hostname": std::env::var("HOSTNAME").unwrap_or_else(|_| "gixbee-rust".into()),
        "outbox": { "pending": 0 },
        "queues": { "bookings": 0, "outbox": 0, "hiring": 0 },
    })))
}

async fn history(
    State(_state): State<AppState>,
    user: AuthUser,
    Query(q): Query<MinutesQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "monitoring")?;
    let minutes = q.minutes.and_then(|m| m.parse().ok()).unwrap_or(30);
    Ok(Json(json!({ "samples": [], "minutes": minutes })))
}

async fn traffic(
    State(_state): State<AppState>,
    user: AuthUser,
    Query(q): Query<MinutesQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "monitoring")?;
    let minutes = q.minutes.and_then(|m| m.parse().ok()).unwrap_or(60);
    Ok(Json(json!({ "points": [], "minutes": minutes })))
}
