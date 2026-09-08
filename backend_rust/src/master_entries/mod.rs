use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::MASTER_ENTRY_COLS;
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
    let is_active = match q.isActive.as_deref() {
        Some("true") | Some("1") | Some("yes") => Some(true),
        Some("false") | Some("0") | Some("no") => Some(false),
        _ => None,
    };

    let rows = if let Some(city_id) = &q.cityId {
        let cid = Uuid::parse_str(city_id)?;
        if let Some(t) = &q.r#type {
            if let Some(active) = is_active {
                if let Some(cat) = &q.category {
                    sqlx::query(&format!(
                        r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND "isActive" = $2 AND category = $3 AND ("cityId" IS NULL OR "cityId" = $4) ORDER BY "createdAt" DESC LIMIT 2000"#
                    ))
                    .bind(t)
                    .bind(active)
                    .bind(cat)
                    .bind(cid)
                    .fetch_all(&state.db)
                    .await?
                } else {
                    sqlx::query(&format!(
                        r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND "isActive" = $2 AND ("cityId" IS NULL OR "cityId" = $3) ORDER BY "createdAt" DESC LIMIT 2000"#
                    ))
                    .bind(t)
                    .bind(active)
                    .bind(cid)
                    .fetch_all(&state.db)
                    .await?
                }
            } else if let Some(cat) = &q.category {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND category = $2 AND ("cityId" IS NULL OR "cityId" = $3) ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(t)
                .bind(cat)
                .bind(cid)
                .fetch_all(&state.db)
                .await?
            } else {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND ("cityId" IS NULL OR "cityId" = $2) ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(t)
                .bind(cid)
                .fetch_all(&state.db)
                .await?
            }
        } else if let Some(active) = is_active {
            if let Some(cat) = &q.category {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE "isActive" = $1 AND category = $2 AND ("cityId" IS NULL OR "cityId" = $3) ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(active)
                .bind(cat)
                .bind(cid)
                .fetch_all(&state.db)
                .await?
            } else {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE "isActive" = $1 AND ("cityId" IS NULL OR "cityId" = $2) ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(active)
                .bind(cid)
                .fetch_all(&state.db)
                .await?
            }
        } else if let Some(cat) = &q.category {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE category = $1 AND ("cityId" IS NULL OR "cityId" = $2) ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(cat)
            .bind(cid)
            .fetch_all(&state.db)
            .await?
        } else {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE "cityId" IS NULL OR "cityId" = $1 ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(cid)
            .fetch_all(&state.db)
            .await?
        }
    } else if let Some(t) = &q.r#type {
        if let Some(active) = is_active {
            if let Some(cat) = &q.category {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND "isActive" = $2 AND category = $3 ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(t)
                .bind(active)
                .bind(cat)
                .fetch_all(&state.db)
                .await?
            } else {
                sqlx::query(&format!(
                    r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND "isActive" = $2 ORDER BY "createdAt" DESC LIMIT 2000"#
                ))
                .bind(t)
                .bind(active)
                .fetch_all(&state.db)
                .await?
            }
        } else if let Some(cat) = &q.category {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND category = $2 ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(t)
            .bind(cat)
            .fetch_all(&state.db)
            .await?
        } else {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(t)
            .fetch_all(&state.db)
            .await?
        }
    } else if let Some(active) = is_active {
        if let Some(cat) = &q.category {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE "isActive" = $1 AND category = $2 ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(active)
            .bind(cat)
            .fetch_all(&state.db)
            .await?
        } else {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE "isActive" = $1 ORDER BY "createdAt" DESC LIMIT 2000"#
            ))
            .bind(active)
            .fetch_all(&state.db)
            .await?
        }
    } else if let Some(cat) = &q.category {
        sqlx::query(&format!(
            r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE category = $1 ORDER BY "createdAt" DESC LIMIT 2000"#
        ))
        .bind(cat)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(&format!(
            r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries ORDER BY "createdAt" DESC LIMIT 2000"#
        ))
        .fetch_all(&state.db)
        .await?
    };

    Ok(Json(rows.iter().map(entry_json).collect()))
}

async fn find_one(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE id = $1"#
    ))
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
    let label = body.get("label").and_then(|v| v.as_str()).unwrap_or("");
    let value = body.get("value").and_then(|v| v.as_str()).unwrap_or("");
    let entry_type = body.get("type").and_then(|v| v.as_str()).unwrap_or("CONFIGURATION");
    let icon = body.get("icon").and_then(|v| v.as_str());
    let category = body.get("category").and_then(|v| v.as_str());
    let city_id = body
        .get("cityId")
        .and_then(|v| v.as_str())
        .map(Uuid::parse_str)
        .transpose()?;
    let is_active = body.get("isActive").and_then(|v| v.as_bool()).unwrap_or(true);
    sqlx::query(
        r#"INSERT INTO master_entries (id, type, label, value, icon, category, "cityId", "isActive") VALUES ($1, $2, $3, $4, $5, $6, $7, $8)"#,
    )
    .bind(id)
    .bind(entry_type)
    .bind(label)
    .bind(value)
    .bind(icon)
    .bind(category)
    .bind(city_id)
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
    require_admin_page(&user, "master-entries")?;
    let uid = Uuid::parse_str(&id)?;
    if let Some(label) = body.get("label").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE master_entries SET label = $1 WHERE id = $2"#)
            .bind(label)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    if let Some(value) = body.get("value").and_then(|v| v.as_str()) {
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
        "type": row.get::<String, _>("type"),
        "label": row.get::<String, _>("label"),
        "value": row.get::<String, _>("value"),
        "icon": row.get::<Option<String>, _>("icon"),
        "category": row.get::<Option<String>, _>("category"),
        "cityId": row.try_get::<Option<Uuid>, _>("cityId").ok().flatten().map(|u| u.to_string()),
        "isActive": row.get::<bool, _>("isActive"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "updatedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("updatedAt").ok(),
    })
}
