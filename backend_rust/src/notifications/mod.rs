use axum::{
    extract::State,
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};

use crate::error::AppResult;
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

mod fcm;
pub use fcm::FcmService;
pub(crate) use fcm::PushOutcome;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/health", get(health))
        .route("/test-self", post(test_self))
}

async fn health(State(state): State<AppState>) -> Json<Value> {
    Json(json!({
        "firebaseInitialized": state.fcm.is_ready(),
        "ready": state.fcm.is_ready(),
        "credentials": state.fcm.diagnostics(&state.config).get("credentials"),
    }))
}

async fn test_self(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let result = state.fcm.test_push(&state, &user.user_id).await;
    Ok(Json(result))
}
