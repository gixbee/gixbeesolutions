use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    response::Response,
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

#[derive(Deserialize)]
struct AdminListQuery {
    r#type: Option<String>,
    isActive: Option<String>,
    q: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(find_all).post(create))
        .route("/admin/list", get(admin_list))
        .route("/{id}", get(find_one).patch(update).delete(remove))
}

#[derive(Clone, Deserialize)]
struct ListQuery {
    r#type: Option<String>,
    isActive: Option<String>,
    category: Option<String>,
    cityId: Option<String>,
}

async fn find_all(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<ListQuery>,
) -> AppResult<Response> {
    let suffix = format!(
        "me:{}:{}:{}:{}",
        q.r#type.as_deref().unwrap_or("-"),
        q.isActive.as_deref().unwrap_or("-"),
        q.category.as_deref().unwrap_or("-"),
        q.cityId.as_deref().unwrap_or("-"),
    );
    let if_none = headers
        .get(axum::http::header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let db_state = state.clone();
    let query = q;
    let cached = crate::cache::read_through(
        &state,
        crate::cache::versions::Domain::ServiceMaster,
        &suffix,
        state.cache.service_master_ttl_secs,
        None,
        if_none,
        || {
            let state = db_state.clone();
            Box::pin(async move {
                let rows = query_master_rows(&state, &query).await?;
                Ok(serde_json::Value::Array(
                    rows.iter().map(entry_json).collect(),
                ))
            })
        },
    )
    .await?;
    if cached.json.is_null() {
        return Ok(crate::cache::http::not_modified(&cached.etag));
    }
    Ok(crate::cache::http::json_cached(
        cached.json,
        &cached.etag,
        cached.outcome,
    ))
}

async fn query_master_rows(
    state: &AppState,
    q: &ListQuery,
) -> AppResult<Vec<sqlx::postgres::PgRow>> {
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

    Ok(rows)
}

async fn admin_list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AdminListQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let is_active = match q.isActive.as_deref() {
        Some("true") | Some("1") => Some(true),
        Some("false") | Some("0") => Some(false),
        _ => None,
    };
    let term = q.q.as_deref().unwrap_or("").trim();
    let rows = match (q.r#type.as_deref(), is_active, term.is_empty()) {
        (Some(t), Some(a), true) => {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 AND "isActive" = $2 ORDER BY "createdAt" DESC LIMIT $3 OFFSET $4"#
            ))
            .bind(t)
            .bind(a)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
        }
        (Some(t), None, true) => {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE type::text = $1 ORDER BY "createdAt" DESC LIMIT $2 OFFSET $3"#
            ))
            .bind(t)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
        }
        (_, _, false) => {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries
                   WHERE ($1::text IS NULL OR type::text = $1)
                     AND ($2::bool IS NULL OR "isActive" = $2)
                     AND (label ILIKE '%' || $3 || '%' OR value ILIKE '%' || $3 || '%')
                   ORDER BY "createdAt" DESC LIMIT $4 OFFSET $5"#
            ))
            .bind(q.r#type.as_deref())
            .bind(is_active)
            .bind(term)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
        }
        _ => {
            sqlx::query(&format!(
                r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries ORDER BY "createdAt" DESC LIMIT $1 OFFSET $2"#
            ))
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
        }
    };
    Ok(Json(json!({
        "items": rows.iter().map(entry_json).collect::<Vec<_>>(),
        "limit": limit,
        "offset": offset,
    })))
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
    let label = body.get("label").and_then(|v| v.as_str()).unwrap_or("").trim();
    let value = body.get("value").and_then(|v| v.as_str()).unwrap_or("").trim();
    if label.is_empty() {
        return Err(AppError::BadRequest("Label is required".into()));
    }
    let entry_type = body.get("type").and_then(|v| v.as_str()).unwrap_or("CONFIGURATION");
    let icon = body.get("icon").and_then(|v| v.as_str());
    let category = body.get("category").and_then(|v| v.as_str());
    let city_id = body
        .get("cityId")
        .and_then(|v| v.as_str())
        .map(Uuid::parse_str)
        .transpose()?;
    let is_active = body.get("isActive").and_then(|v| v.as_bool()).unwrap_or(true);
    let mut tx = state.db.begin().await?;
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
    .execute(&mut *tx)
    .await?;
    master_audit::commit_with_audit(
        tx,
        master_audit::AuditEvent {
            section: "master_entries",
            entity_type: "master_entry",
            entity_id: id.to_string(),
            action: "create",
            actor_user_id: user.user_id.clone(),
            before: None,
            after: Some(entry_json_preview(entry_type, label, value, is_active)),
        },
        crate::cache::versions::Domain::ServiceMaster,
    )
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
    let before_row = sqlx::query(&format!(
        r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE id = $1"#
    ))
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Entry not found".into()))?;
    let before = entry_json(&before_row);
    let mut tx = state.db.begin().await?;
    if let Some(label) = body.get("label").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE master_entries SET label = $1 WHERE id = $2"#)
            .bind(label)
            .bind(uid)
            .execute(&mut *tx)
            .await?;
    }
    if let Some(value) = body.get("value").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE master_entries SET value = $1 WHERE id = $2"#)
            .bind(value)
            .bind(uid)
            .execute(&mut *tx)
            .await?;
    }
    if let Some(active) = body.get("isActive").and_then(|v| v.as_bool()) {
        sqlx::query(r#"UPDATE master_entries SET "isActive" = $1 WHERE id = $2"#)
            .bind(active)
            .bind(uid)
            .execute(&mut *tx)
            .await?;
    }
    master_audit::commit_with_audit(
        tx,
        master_audit::AuditEvent {
            section: "master_entries",
            entity_type: "master_entry",
            entity_id: id.clone(),
            action: "update",
            actor_user_id: user.user_id.clone(),
            before: Some(before),
            after: Some(body.clone()),
        },
        crate::cache::versions::Domain::ServiceMaster,
    )
    .await?;
    find_one(State(state), Path(id)).await
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    let uid = Uuid::parse_str(&id)?;
    let before_row = sqlx::query(&format!(
        r#"SELECT {MASTER_ENTRY_COLS} FROM master_entries WHERE id = $1"#
    ))
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Entry not found".into()))?;
    let before = entry_json(&before_row);
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE master_entries SET "isActive" = false, "updatedAt" = NOW() WHERE id = $1"#)
        .bind(uid)
        .execute(&mut *tx)
        .await?;
    master_audit::commit_with_audit(
        tx,
        master_audit::AuditEvent {
            section: "master_entries",
            entity_type: "master_entry",
            entity_id: id,
            action: "deactivate",
            actor_user_id: user.user_id.clone(),
            before: Some(before),
            after: Some(json!({"isActive": false})),
        },
        crate::cache::versions::Domain::ServiceMaster,
    )
    .await?;
    Ok(Json(json!({ "message": "Deactivated" })))
}

fn entry_json_preview(entry_type: &str, label: &str, value: &str, is_active: bool) -> Value {
    json!({"type": entry_type, "label": label, "value": value, "isActive": is_active})
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
