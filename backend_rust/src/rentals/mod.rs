use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
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
        .route("/items", get(list_items).post(create_item))
        .route("/items/{id}", get(get_item))
        .route("/reservations", post(create_reservation))
        .route("/my-reservations", get(my_reservations))
}

async fn list_items(State(state): State<AppState>, Query(_q): Query<Value>) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(r#"SELECT * FROM rental_items WHERE "isActive" = true"#)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
}

async fn get_item(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT * FROM rental_items WHERE id = $1"#)
        .bind(rid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Item not found".into()))?;
    Ok(Json(item_json(&row)))
}

async fn create_item(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rental_items (id, "ownerId", title, description, "dailyRate", "isActive") VALUES ($1, $2, $3, $4, $5, true)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("title").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(body.get("description").and_then(|v| v.as_str()))
    .bind(body.get("dailyRate").and_then(|v| v.as_f64()).unwrap_or(0.0))
    .execute(&state.db)
    .await?;
    get_item(State(state), Path(id.to_string())).await
}

#[derive(Deserialize)]
struct ReservationBody {
    itemId: String,
    startDate: String,
    endDate: String,
}

async fn create_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ReservationBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let item_id = Uuid::parse_str(&body.itemId)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rental_reservations (id, "itemId", "customerId", "startDate", "endDate", status) VALUES ($1, $2, $3, $4::date, $5::date, 'PENDING')"#,
    )
    .bind(id)
    .bind(item_id)
    .bind(uid)
    .bind(&body.startDate)
    .bind(&body.endDate)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "id": id.to_string(), "status": "PENDING" })))
}

async fn my_reservations(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT * FROM rental_reservations WHERE "customerId" = $1"#)
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "itemId": r.get::<Uuid, _>("itemId").to_string(),
        "status": r.get::<String, _>("status"),
    })).collect()))
}

fn item_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "title": row.get::<String, _>("title"),
        "description": row.get::<Option<String>, _>("description"),
        "dailyRate": row.get::<rust_decimal::Decimal, _>("dailyRate"),
        "imageUrl": row.get::<Option<String>, _>("imageUrl"),
    })
}
