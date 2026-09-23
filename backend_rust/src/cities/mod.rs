use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(find_all).post(create))
        .route("/{id}", get(find_one).patch(update).delete(remove))
}

#[derive(Deserialize)]
struct ActiveQuery {
    isActive: Option<String>,
}

async fn find_all(
    State(state): State<AppState>,
    Query(q): Query<ActiveQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let rows = match q.isActive.as_deref() {
        Some("true") => sqlx::query(r#"SELECT * FROM cities WHERE "isActive" = true ORDER BY name"#)
            .fetch_all(&state.db)
            .await?,
        Some("false") => sqlx::query(r#"SELECT * FROM cities WHERE "isActive" = false ORDER BY name"#)
            .fetch_all(&state.db)
            .await?,
        _ => sqlx::query(r#"SELECT * FROM cities ORDER BY name"#).fetch_all(&state.db).await?,
    };
    Ok(Json(rows.iter().map(row_to_json).collect()))
}

async fn find_one(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id).map_err(|_| AppError::NotFound("City not found".into()))?;
    let row = sqlx::query(r#"SELECT * FROM cities WHERE id = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("City not found".into()))?;
    Ok(Json(row_to_json(&row)))
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "cities")?;
    let id = Uuid::new_v4();
    let name = body.get("name").and_then(|v| v.as_str()).unwrap_or("");
    let state_name = body.get("state").and_then(|v| v.as_str()).unwrap_or("");
    let is_active = body.get("isActive").and_then(|v| v.as_bool()).unwrap_or(true);
    sqlx::query(
        r#"INSERT INTO cities (id, name, state, "isActive") VALUES ($1, $2, $3, $4)"#,
    )
    .bind(id)
    .bind(name)
    .bind(state_name)
    .bind(is_active)
    .execute(&state.db)
    .await?;
    find_one(State(state), Path(id.to_string())).await
}

async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "cities")?;
    let uid = Uuid::parse_str(&id).map_err(|_| AppError::NotFound("City not found".into()))?;
    if let Some(name) = body.get("name").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE cities SET name = $1 WHERE id = $2"#)
            .bind(name)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    if let Some(state_name) = body.get("state").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE cities SET state = $1 WHERE id = $2"#)
            .bind(state_name)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    if let Some(active) = body.get("isActive").and_then(|v| v.as_bool()) {
        sqlx::query(r#"UPDATE cities SET "isActive" = $1 WHERE id = $2"#)
            .bind(active)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    find_one(State(state), Path(id)).await
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "cities")?;
    let uid = Uuid::parse_str(&id).map_err(|_| AppError::NotFound("City not found".into()))?;
    sqlx::query(r#"DELETE FROM cities WHERE id = $1"#)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Deleted" })))
}

fn row_to_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.try_get::<Uuid, _>("id").ok().map(|u| u.to_string()),
        "name": row.try_get::<String, _>("name").ok(),
        "state": row.try_get::<String, _>("state").ok(),
        "lat": row.try_get::<f64, _>("lat").ok(),
        "lng": row.try_get::<f64, _>("lng").ok(),
        "isActive": row.try_get::<bool, _>("isActive").ok(),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "updatedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("updatedAt").ok(),
    })
}
