use axum::{
    extract::{Path, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin, require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list).post(create))
        .route("/{id}", patch(update).delete(remove))
}

async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    require_admin(&user)?;
    let rows = sqlx::query(r#"SELECT id, username, "displayName", "staffRole", "allowedPages", "isActive" FROM admin_staff"#)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(staff_json).collect()))
}

#[derive(Deserialize)]
struct CreateStaff {
    username: String,
    password: String,
    displayName: Option<String>,
    staffRole: Option<String>,
    pages: Option<Vec<String>>,
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateStaff>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "staff")?;
    let id = Uuid::new_v4();
    let hash = bcrypt::hash(&body.password, bcrypt::DEFAULT_COST).map_err(|e| AppError::Internal(e.to_string()))?;
    sqlx::query(
        r#"INSERT INTO admin_staff (id, username, "passwordHash", "displayName", "staffRole", "allowedPages", "isActive") VALUES ($1, $2, $3, $4, $5, $6, true)"#,
    )
    .bind(id)
    .bind(&body.username)
    .bind(&hash)
    .bind(body.displayName.as_deref().unwrap_or(&body.username))
    .bind(body.staffRole.as_deref().unwrap_or("OPERATOR"))
    .bind(body.pages.map(|p| p.join(",")).unwrap_or_default())
    .execute(&state.db)
    .await?;
    Ok(Json(staff_json(
        &sqlx::query(r#"SELECT id, username, "displayName", "staffRole", "allowedPages", "isActive" FROM admin_staff WHERE id = $1"#)
            .bind(id)
            .fetch_one(&state.db)
            .await?,
    )))
}

async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "staff")?;
    let sid = Uuid::parse_str(&id)?;
    if let Some(active) = body.get("isActive").and_then(|v| v.as_bool()) {
        sqlx::query(r#"UPDATE admin_staff SET "isActive" = $1 WHERE id = $2"#)
            .bind(active)
            .bind(sid)
            .execute(&state.db)
            .await?;
    }
    Ok(Json(json!({ "message": "Updated" })))
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "staff")?;
    let sid = Uuid::parse_str(&id)?;
    sqlx::query(r#"DELETE FROM admin_staff WHERE id = $1"#)
        .bind(sid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Deleted" })))
}

fn staff_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "username": row.get::<String, _>("username"),
        "displayName": row.get::<Option<String>, _>("displayName"),
        "staffRole": row.get::<String, _>("staffRole"),
        "allowedPages": row.get::<Option<String>, _>("allowedPages"),
        "isActive": row.get::<bool, _>("isActive"),
    })
}
