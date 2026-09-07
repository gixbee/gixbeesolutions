use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("{0}")]
    BadRequest(String),
    #[error("{0}")]
    Unauthorized(String),
    #[error("{0}")]
    Forbidden(String),
    #[error("{0}")]
    NotFound(String),
    #[error("{0}")]
    Conflict(String),
    #[error("{0}")]
    ServiceUnavailable(String),
    #[error("{0}")]
    Internal(String),
    #[error(transparent)]
    Sqlx(#[from] sqlx::Error),
    #[error(transparent)]
    Anyhow(#[from] anyhow::Error),
}

#[derive(Serialize)]
struct ErrorEnvelope {
    statusCode: u16,
    error: String,
    message: serde_json::Value,
    path: String,
    timestamp: String,
}

impl AppError {
    fn status_and_error(&self) -> (StatusCode, String, serde_json::Value) {
        match self {
            AppError::BadRequest(m) => (StatusCode::BAD_REQUEST, "Bad Request".into(), json!(m)),
            AppError::Unauthorized(m) => (StatusCode::UNAUTHORIZED, "Unauthorized".into(), json!(m)),
            AppError::Forbidden(m) => (StatusCode::FORBIDDEN, "Forbidden".into(), json!(m)),
            AppError::NotFound(m) => (StatusCode::NOT_FOUND, "Not Found".into(), json!(m)),
            AppError::Conflict(m) => (StatusCode::CONFLICT, "Conflict".into(), json!(m)),
            AppError::ServiceUnavailable(m) => {
                (StatusCode::SERVICE_UNAVAILABLE, "Service Unavailable".into(), json!(m))
            }
            AppError::Internal(m) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error".into(), json!(m))
            }
            AppError::Sqlx(e) => map_sqlx_error(e),
            AppError::Anyhow(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Internal Server Error".into(),
                json!("Internal server error"),
            ),
        }
    }
}

fn map_sqlx_error(e: &sqlx::Error) -> (StatusCode, String, serde_json::Value) {
    if let sqlx::Error::Database(db) = e {
        match db.code().as_deref() {
            Some("23505") => (
                StatusCode::CONFLICT,
                "Conflict".into(),
                json!("Resource already exists."),
            ),
            Some("23503") => (
                StatusCode::BAD_REQUEST,
                "Bad Request".into(),
                json!("A referenced resource does not exist."),
            ),
            Some("23502") => (
                StatusCode::BAD_REQUEST,
                "Bad Request".into(),
                json!("A required field is missing."),
            ),
            Some("23514") => (
                StatusCode::BAD_REQUEST,
                "Bad Request".into(),
                json!("A value failed a database constraint."),
            ),
            _ => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "Internal Server Error".into(),
                json!("Internal server error"),
            ),
        }
    } else {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            "Internal Server Error".into(),
            json!("Internal server error"),
        )
    }
}

pub struct ErrorContext {
    pub path: String,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error, message) = self.status_and_error();
        if status.is_server_error() {
            tracing::error!("{status}: {self}");
        } else {
            tracing::warn!("{status}: {self}");
        }
        let path = "/".to_string();
        let body = ErrorEnvelope {
            statusCode: status.as_u16(),
            error,
            message,
            path,
            timestamp: chrono::Utc::now().to_rfc3339(),
        };
        (status, Json(body)).into_response()
    }
}

pub fn with_path(err: AppError, path: &str) -> Response {
    let (status, error, message) = err.status_and_error();
    if status.is_server_error() {
        tracing::error!("{path} -> {status}: {err}");
    } else {
        tracing::warn!("{path} -> {status}: {err}");
    }
    let body = ErrorEnvelope {
        statusCode: status.as_u16(),
        error,
        message,
        path: path.to_string(),
        timestamp: chrono::Utc::now().to_rfc3339(),
    };
    (status, Json(body)).into_response()
}

pub type AppResult<T> = Result<T, AppError>;

impl From<uuid::Error> for AppError {
    fn from(_: uuid::Error) -> Self {
        AppError::BadRequest("Invalid id".into())
    }
}

impl<T> axum::response::IntoResponse for AppResult<T>
where
    T: axum::response::IntoResponse,
{
    fn into_response(self) -> Response {
        match self {
            Ok(value) => value.into_response(),
            Err(err) => err.into_response(),
        }
    }
}
