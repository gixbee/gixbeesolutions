use axum::{
    extract::{Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::error::AppResult;
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_logs))
        .route("/purge", post(purge))
}

pub fn client_routes() -> Router<AppState> {
    Router::new().route("/", post(ingest_client_log))
}

#[derive(Deserialize)]
struct ListQuery {
    page: Option<String>,
    limit: Option<String>,
    level: Option<String>,
}

async fn list_logs(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "logs")?;
    let rows = sqlx::query(r#"SELECT * FROM system_logs ORDER BY "createdAt" DESC LIMIT 100"#)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(json!({ "data": rows.len(), "level": q.level })))
}

async fn purge(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "logs")?;
    let days = state.config.log_retention_days;
    if days > 0 {
        sqlx::query(
            r#"DELETE FROM system_logs WHERE "createdAt" < NOW() - make_interval(days => $1)"#,
        )
        .bind(days as i32)
        .execute(&state.db)
        .await?;
    }
    Ok(Json(json!({ "message": "Purged" })))
}

async fn ingest_client_log(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    sqlx::query(
        r#"INSERT INTO system_logs (id, level, message, source, "userId", metadata) VALUES (gen_random_uuid(), $1, $2, 'client', $3, $4)"#,
    )
    .bind(body.get("level").and_then(|v| v.as_str()).unwrap_or("info"))
    .bind(body.get("message").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(&user.user_id)
    .bind(body.get("metadata").cloned().unwrap_or(json!({})))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "message": "Logged" })))
}
