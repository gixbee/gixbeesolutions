use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pagination::{pagination_offset, parse_pagination};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin, require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/my", get(my_tickets))
        .route("/admin/all", get(admin_list))
        .route("/admin/{id}/resolve", patch(resolve))
}

#[derive(Deserialize)]
struct CreateTicket {
    subject: String,
    message: String,
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<CreateTicket>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO support_tickets (id, "userId", subject, message, status) VALUES ($1, $2, $3, $4, 'OPEN')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(&body.subject)
    .bind(&body.message)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "id": id.to_string(), "status": "OPEN" })))
}

async fn my_tickets(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT * FROM support_tickets WHERE "userId" = $1 ORDER BY "createdAt" DESC"#)
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(ticket_json).collect()))
}

#[derive(Deserialize)]
struct AdminListQuery {
    status: Option<String>,
    page: Option<String>,
    limit: Option<String>,
}

async fn admin_list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AdminListQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "support")?;
    let (page, limit) = parse_pagination(q.page.as_deref(), q.limit.as_deref());
    let offset = pagination_offset(page, limit);
    let rows = if let Some(status) = &q.status {
        sqlx::query(r#"SELECT * FROM support_tickets WHERE status = $1 ORDER BY "createdAt" DESC LIMIT $2 OFFSET $3"#)
            .bind(status)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
    } else {
        sqlx::query(r#"SELECT * FROM support_tickets ORDER BY "createdAt" DESC LIMIT $1 OFFSET $2"#)
            .bind(limit)
            .bind(offset)
            .fetch_all(&state.db)
            .await?
    };
    Ok(Json(json!({
        "data": rows.iter().map(ticket_json).collect::<Vec<_>>(),
        "page": page,
        "limit": limit,
    })))
}

#[derive(Deserialize)]
struct ResolveBody {
    reply: String,
}

async fn resolve(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ResolveBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "support")?;
    let tid = Uuid::parse_str(&id)?;
    sqlx::query(
        r#"UPDATE support_tickets SET status = 'RESOLVED', reply = $1, "resolvedAt" = NOW() WHERE id = $2"#,
    )
    .bind(&body.reply)
    .bind(tid)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "message": "Resolved" })))
}

fn ticket_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "userId": row.get::<Uuid, _>("userId").to_string(),
        "subject": row.get::<String, _>("subject"),
        "message": row.get::<String, _>("message"),
        "status": row.get::<String, _>("status"),
        "reply": row.get::<Option<String>, _>("reply"),
    })
}