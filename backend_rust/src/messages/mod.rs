use axum::{
    extract::{Path, State},
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
        .route("/threads", get(list_threads))
        .route("/threads/{userId}", get(get_thread))
        .route("/send", post(send_message))
}

async fn list_threads(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"
        SELECT DISTINCT ON ("senderId", "receiverId")
            id, "senderId", "receiverId", content, "createdAt"
        FROM messages
        WHERE "senderId" = $1 OR "receiverId" = $1
        ORDER BY "senderId", "receiverId", "createdAt" DESC
        "#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(message_json).collect()))
}

async fn get_thread(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other_id): Path<String>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let oid = Uuid::parse_str(&other_id)?;
    let rows = sqlx::query(
        r#"SELECT * FROM messages WHERE ("senderId" = $1 AND "receiverId" = $2) OR ("senderId" = $2 AND "receiverId" = $1) ORDER BY "createdAt""#,
    )
    .bind(uid)
    .bind(oid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(message_json).collect()))
}

#[derive(Deserialize)]
struct SendBody {
    receiverId: String,
    content: String,
    bookingId: Option<String>,
}

async fn send_message(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rid = Uuid::parse_str(&body.receiverId)?;
    let id = Uuid::new_v4();
    let booking_id = body.bookingId.as_ref().and_then(|b| Uuid::parse_str(b).ok());
    sqlx::query(
        r#"INSERT INTO messages (id, "senderId", "receiverId", content, "bookingId") VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(rid)
    .bind(&body.content)
    .bind(booking_id)
    .execute(&state.db)
    .await?;
    Ok(Json(message_json(
        &sqlx::query(r#"SELECT * FROM messages WHERE id = $1"#)
            .bind(id)
            .fetch_one(&state.db)
            .await?,
    )))
}

fn message_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "senderId": row.get::<Uuid, _>("senderId").to_string(),
        "receiverId": row.get::<Uuid, _>("receiverId").to_string(),
        "content": row.get::<String, _>("content"),
        "createdAt": row.get::<chrono::DateTime<chrono::Utc>, _>("createdAt"),
    })
}
