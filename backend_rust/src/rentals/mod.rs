use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::{RENTAL_ITEM_COLS, RENTAL_RESERVATION_COLS};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_items).post(create_item))
        .route("/my-items", get(my_items))
        .route("/reservations/my", get(my_reservations))
        .route("/reservations/owner", get(owner_reservations))
        .route("/reservations/{res_id}/confirm", patch(confirm_reservation))
        .route("/reservations/{res_id}/reject", patch(reject_reservation))
        .route("/reservations/{res_id}/start", patch(start_reservation))
        .route("/reservations/{res_id}/complete", patch(complete_reservation))
        .route("/reservations/{res_id}/cancel", patch(cancel_reservation))
        .route("/{id}/reserve", post(create_reservation))
        .route("/{id}", get(get_item).patch(update_item))
}

async fn list_items(State(state): State<AppState>) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE "isAvailable" = true ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
}

async fn my_items(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE "ownerId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
}

async fn get_item(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;

    let booked = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE "itemId" = $1 AND status IN ('CONFIRMED', 'ACTIVE') ORDER BY "startTime" ASC LIMIT 200"#
    ))
    .bind(rid)
    .fetch_all(&state.db)
    .await?;

    let mut item = item_json(&row);
    if let Some(obj) = item.as_object_mut() {
        obj.insert(
            "bookedRanges".into(),
            json!(
                booked
                    .iter()
                    .map(|r| json!({
                        "start": r.get::<chrono::DateTime<chrono::Utc>, _>("startTime"),
                        "end": r.get::<chrono::DateTime<chrono::Utc>, _>("endTime"),
                    }))
                    .collect::<Vec<_>>()
            ),
        );
    }
    Ok(Json(item))
}

async fn create_item(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO rental_items (id, "ownerId", name, description, "imageUrl", "hourlyRate", "dailyRate", "minHoursToRent", "isAvailable")
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("name").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(body.get("description").and_then(|v| v.as_str()))
    .bind(body.get("imageUrl").and_then(|v| v.as_str()))
    .bind(body.get("hourlyRate").and_then(|v| v.as_f64()).unwrap_or(0.0))
    .bind(body.get("dailyRate").and_then(|v| v.as_f64()))
    .bind(body.get("minHoursToRent").and_then(|v| v.as_i64()).unwrap_or(1) as i32)
    .execute(&state.db)
    .await?;
    get_item(State(state), Path(id.to_string())).await
}

async fn update_item(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let item_id = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let owner = sqlx::query_scalar::<_, Uuid>(
        r#"SELECT "ownerId" FROM rental_items WHERE id = $1"#,
    )
    .bind(item_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;
    if owner != uid {
        return Err(AppError::Forbidden("You can only edit your own items".into()));
    }
    if let Some(name) = body.get("name").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE rental_items SET name = $1 WHERE id = $2"#)
            .bind(name)
            .bind(item_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(desc) = body.get("description").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE rental_items SET description = $1 WHERE id = $2"#)
            .bind(desc)
            .bind(item_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(rate) = body.get("hourlyRate").and_then(|v| v.as_f64()) {
        sqlx::query(r#"UPDATE rental_items SET "hourlyRate" = $1 WHERE id = $2"#)
            .bind(rate)
            .bind(item_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(avail) = body.get("isAvailable").and_then(|v| v.as_bool()) {
        sqlx::query(r#"UPDATE rental_items SET "isAvailable" = $1 WHERE id = $2"#)
            .bind(avail)
            .bind(item_id)
            .execute(&state.db)
            .await?;
    }
    get_item(State(state), Path(id)).await
}

#[derive(Deserialize)]
struct ReserveBody {
    startTime: String,
    endTime: String,
}

async fn create_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ReserveBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let item_id = Uuid::parse_str(&id)?;
    let res_id = Uuid::new_v4();

    let item = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id = $1"#
    ))
    .bind(item_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;

    let owner_id = item.get::<Uuid, _>("ownerId");
    if owner_id == uid {
        return Err(AppError::BadRequest("You cannot reserve your own item.".into()));
    }
    if !item.get::<bool, _>("isAvailable") {
        return Err(AppError::BadRequest("This item is currently listed as unavailable.".into()));
    }

    let hourly = item
        .try_get::<rust_decimal::Decimal, _>("hourlyRate")
        .ok()
        .unwrap_or_default();
    let daily = item.try_get::<Option<rust_decimal::Decimal>, _>("dailyRate").ok().flatten();

    sqlx::query(
        r#"INSERT INTO rental_reservations (id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status)
           VALUES ($1, $2, $3, $4::timestamptz, $5::timestamptz, $6, 'PENDING')"#,
    )
    .bind(res_id)
    .bind(item_id)
    .bind(uid)
    .bind(&body.startTime)
    .bind(&body.endTime)
    .bind(daily.unwrap_or(hourly))
    .execute(&state.db)
    .await?;

    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(res_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(reservation_json(&row)))
}

async fn my_reservations(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE "renterId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(reservation_json).collect()))
}

async fn owner_reservations(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT r.id, r."itemId", r."renterId", r."startTime", r."endTime", r."totalPrice", r.status::text AS status, r."createdAt", r."updatedAt"
           FROM rental_reservations r
           JOIN rental_items i ON i.id = r."itemId"
           WHERE i."ownerId" = $1
           ORDER BY r."createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(reservation_json).collect()))
}
async fn confirm_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "CONFIRMED").await
}

async fn reject_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "REJECTED").await
}

async fn start_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "ACTIVE").await
}

async fn complete_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "COMPLETED").await
}

async fn cancel_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "CANCELLED").await
}

async fn update_reservation_status(
    state: &AppState,
    user: &AuthUser,
    res_id: &str,
    status: &str,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(res_id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let owner = sqlx::query_scalar::<_, Option<Uuid>>(
        r#"SELECT i."ownerId" FROM rental_reservations r JOIN rental_items i ON i.id = r."itemId" WHERE r.id = $1"#,
    )
    .bind(rid)
    .fetch_optional(&state.db)
    .await?
    .flatten();
    let renter = sqlx::query_scalar::<_, Option<Uuid>>(
        r#"SELECT "renterId" FROM rental_reservations WHERE id = $1"#,
    )
    .bind(rid)
    .fetch_optional(&state.db)
    .await?
    .flatten();
    if owner != Some(uid) && renter != Some(uid) {
        return Err(AppError::Forbidden("Not allowed".into()));
    }
    sqlx::query(r#"UPDATE rental_reservations SET status = $1 WHERE id = $2"#)
        .bind(status)
        .bind(rid)
        .execute(&state.db)
        .await?;
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(reservation_json(&row)))
}

fn item_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "ownerId": row.get::<Uuid, _>("ownerId").to_string(),
        "name": row.get::<String, _>("name"),
        "description": row.get::<Option<String>, _>("description"),
        "imageUrl": row.get::<Option<String>, _>("imageUrl"),
        "hourlyRate": row.get::<rust_decimal::Decimal, _>("hourlyRate"),
        "dailyRate": row.try_get::<Option<rust_decimal::Decimal>, _>("dailyRate").ok().flatten(),
        "minHoursToRent": row.get::<i32, _>("minHoursToRent"),
        "isAvailable": row.get::<bool, _>("isAvailable"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "updatedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("updatedAt").ok(),
    })
}

fn reservation_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "itemId": row.get::<Uuid, _>("itemId").to_string(),
        "renterId": row.get::<Uuid, _>("renterId").to_string(),
        "startTime": row.get::<chrono::DateTime<chrono::Utc>, _>("startTime"),
        "endTime": row.get::<chrono::DateTime<chrono::Utc>, _>("endTime"),
        "totalPrice": row.try_get::<rust_decimal::Decimal, _>("totalPrice").ok(),
        "status": row.get::<String, _>("status"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
    })
}
