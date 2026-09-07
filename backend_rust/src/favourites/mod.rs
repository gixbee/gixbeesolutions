use axum::{
    extract::{Path, State},
    routing::{delete, get, post},
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(get_my_favourites))
        .route("/{workerId}", get(is_favourite).post(add).delete(remove))
}

async fn get_my_favourites(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT * FROM favourites WHERE "userId" = $1 ORDER BY "createdAt" DESC"#)
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "workerId": r.get::<String, _>("workerId"),
    })).collect()))
}

async fn is_favourite(
    State(state): State<AppState>,
    user: AuthUser,
    Path(worker_id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let count = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) FROM favourites WHERE "userId" = $1 AND "workerId" = $2"#,
    )
    .bind(uid)
    .bind(&worker_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "favourited": count > 0 })))
}

async fn add(
    State(state): State<AppState>,
    user: AuthUser,
    Path(worker_id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let existing = sqlx::query(
        r#"SELECT * FROM favourites WHERE "userId" = $1 AND "workerId" = $2"#,
    )
    .bind(uid)
    .bind(&worker_id)
    .fetch_optional(&state.db)
    .await?;
    if let Some(r) = existing {
        return Ok(Json(json!({
            "id": r.get::<Uuid, _>("id").to_string(),
            "workerId": r.get::<String, _>("workerId"),
        })));
    }
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO favourites (id, "userId", "workerId") VALUES ($1, $2, $3)"#)
        .bind(id)
        .bind(uid)
        .bind(&worker_id)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "id": id.to_string(), "workerId": worker_id })))
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(worker_id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let result = sqlx::query(r#"DELETE FROM favourites WHERE "userId" = $1 AND "workerId" = $2"#)
        .bind(uid)
        .bind(&worker_id)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "removed": result.rows_affected() > 0 })))
}
