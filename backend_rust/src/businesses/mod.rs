use axum::{
    extract::{Path, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::BUSINESS_COLS;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/my", get(list))
        .route("/{id}", get(get_one).patch(update).delete(remove))
        .route("/{id}/operators", post(add_operator))
        .route("/{id}/calendar/offline", post(add_offline_day).delete(remove_offline_day))
}

async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {BUSINESS_COLS} FROM businesses WHERE "ownerId" = $1 ORDER BY "createdAt" DESC"#
    ))
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
        r#"INSERT INTO businesses (id, "ownerId", name, type, location, status) VALUES ($1, $2, $3, $4, $5, 'PENDING')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(name)
    .bind(biz_type)
    .bind(body.get("location").and_then(|v| v.as_str()).unwrap_or(""))
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
    let row = sqlx::query(&format!(r#"SELECT {BUSINESS_COLS} FROM businesses WHERE id = $1"#))
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
    let _uid = Uuid::parse_str(operator_id)?;
    let row = sqlx::query_scalar::<_, Option<Vec<String>>>(
        r#"SELECT "operatorIds" FROM businesses WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    let mut ops = row.unwrap_or_default();
    if !ops.iter().any(|o| o == operator_id) {
        ops.push(operator_id.clone());
        sqlx::query(r#"UPDATE businesses SET "operatorIds" = $1 WHERE id = $2"#)
            .bind(&ops)
            .bind(bid)
            .execute(&state.db)
            .await?;
    }
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
        "serviceType": row.get::<Option<String>, _>("serviceType"),
        "location": row.get::<String, _>("location"),
        "cityId": row.try_get::<Option<Uuid>, _>("cityId").ok().flatten().map(|u| u.to_string()),
        "description": row.get::<Option<String>, _>("description"),
        "documentUrl": row.get::<Option<String>, _>("documentUrl"),
        "status": row.get::<String, _>("status"),
        "operatorIds": row.try_get::<Option<Vec<String>>, _>("operatorIds").ok().flatten(),
        "offlineDays": row.try_get::<Option<serde_json::Value>, _>("offlineDays").ok().flatten(),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "updatedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("updatedAt").ok(),
    })
}
