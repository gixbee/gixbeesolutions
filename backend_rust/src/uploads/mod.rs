use axum::{
    extract::{Multipart, State},
    routing::post,
    Json, Router,
};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/uploads/image", post(upload_image))
}

async fn upload_image(
    State(state): State<AppState>,
    _user: AuthUser,
    mut multipart: Multipart,
) -> AppResult<Json<Value>> {
    while let Some(field) = multipart.next_field().await.map_err(|e| AppError::BadRequest(e.to_string()))? {
        if field.name() == Some("file") {
            let file_name = field.file_name().map(|n| n.to_string());
            let data = field.bytes().await.map_err(|e| AppError::BadRequest(e.to_string()))?;
            let ext = file_name
                .as_deref()
                .and_then(|n| n.rsplit('.').next())
                .map(|e| e.to_ascii_lowercase())
                .filter(|e| ["jpg", "jpeg", "png", "webp", "pdf"].contains(&e.as_str()))
                .ok_or_else(|| AppError::BadRequest("JPG, PNG or PDF only".into()))?;
            if data.len() > 5 * 1024 * 1024 {
                return Err(AppError::BadRequest("File must be 5MB or smaller".into()));
            }
            let filename = format!("{}.{}", Uuid::new_v4(), ext);
            let path = format!("{}/{}", state.config.uploads_dir, filename);
            tokio::fs::create_dir_all(&state.config.uploads_dir)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;
            tokio::fs::write(&path, &data)
                .await
                .map_err(|e| AppError::Internal(e.to_string()))?;
            return Ok(Json(json!({ "url": format!("/uploads/{}", filename) })));
        }
    }
    Err(AppError::BadRequest("file required".into()))
}
