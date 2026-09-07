use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/bookings/{id}/webrtc-config", get(webrtc_config))
}

async fn webrtc_config(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let _bid = Uuid::parse_str(&id)?;
    let stun = state
        .config
        .webrtc_stun_urls
        .split(',')
        .map(|s| json!({ "urls": s.trim() }))
        .collect::<Vec<_>>();
    let mut ice = stun;
    if let Some(turn_urls) = &state.config.webrtc_turn_urls {
        for url in turn_urls.split(',') {
            ice.push(json!({
                "urls": url.trim(),
                "username": state.config.webrtc_turn_username,
                "credential": state.config.webrtc_turn_credential,
            }));
        }
    }
    Ok(Json(json!({ "iceServers": ice })))
}
