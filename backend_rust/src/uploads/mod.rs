use axum::{
    extract::{DefaultBodyLimit, Multipart, State},
    routing::post,
    Json, Router,
};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/uploads/image", post(upload_image))
        .route("/uploads/resume", post(upload_resume))
        .route(
            "/hiring/seeker-resumes",
            post(upload_seeker_resume).layer(DefaultBodyLimit::max(5 * 1024 * 1024 + 64 * 1024)),
        )
}

async fn upload_seeker_resume(
    State(state): State<AppState>,
    user: AuthUser,
    mut multipart: Multipart,
) -> AppResult<Json<Value>> {
    while let Some(field) = multipart.next_field().await.map_err(|e| AppError::BadRequest(e.to_string()))? {
        if field.name() != Some("file") {
            continue;
        }
        let name = field.file_name().unwrap_or("").to_owned();
        let data = field.bytes().await.map_err(|e| AppError::BadRequest(e.to_string()))?;
        let extension = name.rsplit_once('.').map(|(_, ext)| ext.to_ascii_lowercase());
        let valid = match extension.as_deref() {
            Some("pdf") => data.starts_with(b"%PDF-"),
            Some("doc") => data.starts_with(&[0xd0, 0xcf, 0x11, 0xe0]),
            Some("docx") => data.starts_with(b"PK\x03\x04"),
            Some("jpg" | "jpeg") => data.starts_with(&[0xff, 0xd8, 0xff]),
            Some("png") => data.starts_with(b"\x89PNG\r\n\x1a\n"),
            Some("webp") => data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP"),
            _ => false,
        };
        if !valid || name.chars().count() > 255 || data.len() > 5 * 1024 * 1024 {
            return Err(AppError::BadRequest("Choose a PDF, Word document or supported image up to 5 MB".into()));
        }
        let id = Uuid::new_v4();
        sqlx::query(r#"INSERT INTO seeker_resume_uploads (id,"userId",filename,content) VALUES ($1,$2,$3,$4)"#)
            .bind(id)
            .bind(Uuid::parse_str(&user.user_id)?)
            .bind(&name)
            .bind(data.as_ref())
            .execute(&state.db)
            .await?;
        return Ok(Json(json!({ "resumeId": id, "fileName": name })));
    }
    Err(AppError::BadRequest("file required".into()))
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
            write_upload(&state, &path, &data).await?;
            return Ok(Json(json!({ "url": format!("/uploads/{}", filename) })));
        }
    }
    Err(AppError::BadRequest("file required".into()))
}

async fn upload_resume(
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
                .filter(|e| ["pdf", "doc", "docx"].contains(&e.as_str()))
                .ok_or_else(|| AppError::BadRequest("PDF, DOC or DOCX only".into()))?;
            if data.len() > 5 * 1024 * 1024 {
                return Err(AppError::BadRequest("File must be 5MB or smaller".into()));
            }
            let stored = format!("{}.{}", Uuid::new_v4(), ext);
            let path = format!("{}/{}", state.config.uploads_dir, stored);
            write_upload(&state, &path, &data).await?;
            let mime = match ext.as_str() {
                "pdf" => "application/pdf",
                "doc" => "application/msword",
                _ => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            };
            return Ok(Json(json!({
                "fileUrl": format!("/uploads/{stored}"),
                "fileName": file_name.unwrap_or(stored),
                "mimeType": mime,
                "uploadedAt": chrono::Utc::now().to_rfc3339(),
            })));
        }
    }
    Err(AppError::BadRequest("file required".into()))
}

async fn write_upload(state: &AppState, path: &str, data: &[u8]) -> AppResult<()> {
    tokio::fs::create_dir_all(&state.config.uploads_dir)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    tokio::fs::write(path, data)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(())
}
