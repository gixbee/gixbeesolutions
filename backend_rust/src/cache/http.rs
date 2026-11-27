use axum::{
    extract::State,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};

use crate::error::AppResult;
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

use super::stats;
use super::versions;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/versions", get(list_versions))
        .route("/admin/stats", get(admin_stats))
        .route("/admin/stats/reset", post(admin_stats_reset))
}

async fn list_versions(State(state): State<AppState>) -> AppResult<Json<serde_json::Value>> {
    Ok(Json(versions::all_versions(&state.db).await?))
}

async fn admin_stats(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<serde_json::Value>> {
    require_admin_page(&user, "monitoring")?;
    Ok(Json(stats::snapshot(state.cache_redis.as_ref(), state.cache_redis.is_ready()).await))
}

async fn admin_stats_reset(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<serde_json::Value>> {
    require_admin_page(&user, "monitoring")?;
    stats::reset_all(state.cache_redis.as_ref()).await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

pub fn apply_cache_headers(headers: &mut HeaderMap, etag: &str, outcome: super::CacheOutcome) {
    if etag.is_empty() {
        headers.insert(header::CACHE_CONTROL, header::HeaderValue::from_static("no-store"));
        return;
    }
    if let Ok(v) = header::HeaderValue::from_str(etag) {
        headers.insert(header::ETAG, v);
    }
    let cache_control = match outcome {
        super::CacheOutcome::Hit => "public, max-age=60",
        super::CacheOutcome::Miss | super::CacheOutcome::Fallback => "public, max-age=30",
    };
    if let Ok(v) = header::HeaderValue::from_str(cache_control) {
        headers.insert(header::CACHE_CONTROL, v);
    }
}

pub fn not_modified(etag: &str) -> Response {
    let mut headers = HeaderMap::new();
    apply_cache_headers(&mut headers, etag, super::CacheOutcome::Hit);
    (StatusCode::NOT_MODIFIED, headers).into_response()
}

pub fn json_cached(body: serde_json::Value, etag: &str, outcome: super::CacheOutcome) -> Response {
    let mut headers = HeaderMap::new();
    apply_cache_headers(&mut headers, etag, outcome);
    (headers, Json(body)).into_response()
}
