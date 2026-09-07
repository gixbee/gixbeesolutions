use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde::Deserialize;
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
struct ListQuery {
    r#type: Option<String>,
    isActive: Option<String>,
    category: Option<String>,
    cityId: Option<String>,
}

async fn find_all(
    State(state): State<AppState>,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let mut sql = String::from("SELECT * FROM master_entries WHERE 1=1");
    if q.r#type.is_some() {
        sql.push_str(r#" AND type = $1"#);
    }
    let rows = sqlx::query(r#"SELECT * FROM master_entries ORDER BY "sortOrder", "createdAt""#)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(entry_json).collect()))
}

async fn find_one(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT * FROM master_entries WHERE id = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Entry not found".into()))?;
    Ok(Json(entry_json(&row)))
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    let id = Uuid::new_v4();
    let key = body.get("key").and_then(|v| v.as_str()).unwrap_or("");
    let value = body.get("value").cloned().unwrap_or(json!(""));
    let entry_type = body.get("type").and_then(|v| v.as_str()).unwrap_or("CONFIG");
    sqlx::query(
        r#"INSERT INTO master_entries (id, key, value, type, "isActive", "sortOrder") VALUES ($1, $2, $3, $4, true, 0)"#,
    )
    .bind(id)
    .bind(key)
    .bind(value)
    .bind(entry_type)
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
    require_admin_page(&user, "master-entries")?;
    let uid = Uuid::parse_str(&id)?;
    if let Some(value) = body.get("value") {
        sqlx::query(r#"UPDATE master_entries SET value = $1 WHERE id = $2"#)
            .bind(value)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    if let Some(active) = body.get("isActive").and_then(|v| v.as_bool()) {
        sqlx::query(r#"UPDATE master_entries SET "isActive" = $1 WHERE id = $2"#)
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
    require_admin_page(&user, "master-entries")?;
    let uid = Uuid::parse_str(&id)?;
    sqlx::query(r#"DELETE FROM master_entries WHERE id = $1"#)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Deleted" })))
}

fn entry_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "key": row.get::<String, _>("key"),
        "value": row.get::<serde_json::Value, _>("value"),
        "type": row.get::<String, _>("type"),
        "isActive": row.get::<bool, _>("isActive"),
        "sortOrder": row.get::<i32, _>("sortOrder"),
    })
}