use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};

use crate::error::AppResult;
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/health", get(health))
        .route("/test-self", post(test_self))
}

async fn health(State(state): State<AppState>) -> Json<Value> {
    let firebase = state.config.firebase_key_path.is_some()
        || state.config.firebase_project_id.is_some();
    Json(json!({
        "firebaseInitialized": firebase,
        "ready": firebase,
    }))
}

async fn test_self(
    State(_state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({
        "message": "Test push queued",
        "userId": user.user_id,
    })))
}
