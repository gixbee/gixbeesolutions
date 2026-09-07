use axum::{
    extract::{Path, State},
    routing::{delete, get, patch, post},
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
        .route("/", get(list).post(create))
        .route("/{id}", get(get_one).patch(update).delete(remove))
        .route("/{id}/operators", post(add_operator))
        .route("/{id}/offline-days", post(add_offline_day).delete(remove_offline_day))
}

async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"SELECT * FROM businesses WHERE "ownerId" = $1 OR id IN (SELECT "businessId" FROM business_operators WHERE "userId" = $1)"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(business_json).collect()))
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let name = body.get("name").and_then(|v| v.as_str()).unwrap_or("");
    let biz_type = body.get("type").and_then(|v| v.as_str()).unwrap_or("SERVICE");
    sqlx::query(
        r#"INSERT INTO businesses (id, "ownerId", name, type, status) VALUES ($1, $2, $3, $4, 'ACTIVE')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(name)
    .bind(biz_type)
    .execute(&state.db)
    .await?;
    get_one(State(state), user, Path(id.to_string())).await
}

async fn get_one(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT * FROM businesses WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    Ok(Json(business_json(&row)))
}

async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    if let Some(name) = body.get("name").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE businesses SET name = $1 WHERE id = $2"#)
            .bind(name)
            .bind(bid)
            .execute(&state.db)
            .await?;
    }
    get_one(State(state), user, Path(id)).await
}

async fn remove(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    sqlx::query(r#"DELETE FROM businesses WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Deleted" })))
}

async fn add_operator(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let operator_id = body
        .get("userId")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("userId required".into()))?;
    let uid = Uuid::parse_str(operator_id)?;
    sqlx::query(
        r#"INSERT INTO business_operators (id, "businessId", "userId") VALUES ($1, $2, $3) ON CONFLICT DO NOTHING"#,
    )
    .bind(Uuid::new_v4())
    .bind(bid)
    .bind(uid)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "message": "Operator added" })))
}

async fn add_offline_day(
    State(_state): State<AppState>,
    _user: AuthUser,
    Path(_id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "date": body.get("date"), "message": "Added" })))
}

async fn remove_offline_day(
    State(_state): State<AppState>,
    _user: AuthUser,
    Path(_id): Path<String>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "message": "Removed" })))
}

fn business_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "ownerId": row.get::<Uuid, _>("ownerId").to_string(),
        "name": row.get::<String, _>("name"),
        "type": row.get::<String, _>("type"),
        "status": row.get::<String, _>("status"),
    })
}
