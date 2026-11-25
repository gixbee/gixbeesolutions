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
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(get_my_addresses).post(add))
        .route("/{id}/coords", patch(update_coords))
        .route("/{id}", delete(remove))
}

async fn get_my_addresses(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT * FROM addresses WHERE "userId" = $1 ORDER BY "createdAt" DESC"#)
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(address_json).collect()))
}

#[derive(Deserialize)]
struct CreateAddress {
    line: String,
    label: Option<String>,
    lat: Option<f64>,
    lng: Option<f64>,
}

async fn add(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateAddress>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO addresses (id, "userId", line, label, lat, lng) VALUES ($1, $2, $3, $4, $5, $6)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(&body.line)
    .bind(body.label.as_deref().unwrap_or("Home"))
    .bind(body.lat)
    .bind(body.lng)
    .execute(&state.db)
    .await?;
    let row = sqlx::query(r#"SELECT * FROM addresses WHERE id = $1"#)
        .bind(id)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(address_json(&row)))
}

#[derive(Deserialize)]
struct CoordsBody {
    lat: f64,
    lng: f64,
}

async fn update_coords(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<CoordsBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let aid = Uuid::parse_str(&id)?;
    let result = sqlx::query(
        r#"UPDATE addresses SET lat = $1, lng = $2 WHERE id = $3 AND "userId" = $4"#,
    )
    .bind(body.lat)
    .bind(body.lng)
    .bind(aid)
    .bind(uid)
    .execute(&state.db)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Address not found".into()));
    }
    let row = sqlx::query(r#"SELECT * FROM addresses WHERE id = $1"#)
        .bind(aid)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(address_json(&row)))
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let aid = Uuid::parse_str(&id)?;
    let result = sqlx::query(r#"DELETE FROM addresses WHERE id = $1 AND "userId" = $2"#)
        .bind(aid)
        .bind(uid)
        .execute(&state.db)
        .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("Address not found".into()));
    }
    Ok(Json(json!({ "message": "Deleted" })))
}

fn numeric_f64(row: &sqlx::postgres::PgRow, col: &str) -> Option<f64> {
    row.try_get::<Option<rust_decimal::Decimal>, _>(col)
        .ok()
        .flatten()
        .and_then(|d| d.to_string().parse::<f64>().ok())
}

fn address_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "userId": row.get::<Uuid, _>("userId").to_string(),
        "line": row.get::<String, _>("line"),
        "label": row.get::<Option<String>, _>("label"),
        "lat": numeric_f64(row, "lat"),
        "lng": numeric_f64(row, "lng"),
    })
}
