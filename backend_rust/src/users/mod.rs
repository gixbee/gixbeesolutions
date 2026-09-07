use axum::{
    extract::{Path, Query, State},
    routing::{get, patch},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pagination::{pagination_offset, parse_pagination};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/summary", get(get_summary))
        .route("/search", get(search_users))
        .route("/", get(get_all_users))
        .route("/skill/{skill_id}/status", patch(update_skill_status))
        .route("/{id}/stats", get(get_user_stats))
        .route("/{id}/fcm-token", patch(update_fcm_token))
        .route("/{id}/status", patch(update_status))
        .route("/{id}/verify", patch(verify_user))
        .route("/{id}", get(get_user).patch(update_profile))
}

fn is_portal_admin(user: &AuthUser) -> bool {
    user.role.as_deref() == Some("ADMIN") && user.staff_role.is_some()
}

fn assert_self_or_admin(user: &AuthUser, id: &str) -> AppResult<()> {
    if user.user_id != id && !is_portal_admin(user) {
        return Err(AppError::Forbidden("You can only view your own profile".into()));
    }
    Ok(())
}

async fn get_summary(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    if user.staff_role.is_none() {
        return Err(AppError::Forbidden("Admin access required".into()));
    }
    let total = sqlx::query_scalar::<_, i64>(r#"SELECT COUNT(*) FROM users"#)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(json!({ "totalUsers": total })))
}

#[derive(Deserialize)]
struct PageQuery {
    page: Option<String>,
    limit: Option<String>,
}

async fn get_all_users(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "users")?;
    let (page, limit) = parse_pagination(q.page.as_deref(), q.limit.as_deref());
    let offset = pagination_offset(page, limit);
    let rows = sqlx::query(
        r#"SELECT id, "phoneNumber", name, role, "isVerified", "hasWorkerProfile", "approvalStatus", "createdAt" FROM users ORDER BY "createdAt" DESC LIMIT $1 OFFSET $2"#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(json!({
        "data": rows.iter().map(user_list_json).collect::<Vec<_>>(),
        "page": page,
        "limit": limit,
    })))
}

#[derive(Deserialize)]
struct SearchQuery {
    q: Option<String>,
    limit: Option<String>,
}

async fn search_users(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SearchQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let query = q.q.unwrap_or_default();
    if query.is_empty() {
        return Ok(Json(vec![]));
    }
    let limit = q.limit.and_then(|l| l.parse().ok()).unwrap_or(20);
    let include_phone = is_portal_admin(&user);
    let rows = sqlx::query(
        r#"SELECT id, name, "phoneNumber" FROM users WHERE name ILIKE $1 OR "phoneNumber" ILIKE $1 LIMIT $2"#,
    )
    .bind(format!("%{}%", query))
    .bind(limit)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.iter()
            .map(|r| {
                let mut obj = json!({
                    "id": r.get::<Uuid, _>("id").to_string(),
                    "name": r.get::<Option<String>, _>("name"),
                });
                if include_phone {
                    obj["phoneNumber"] = json!(r.get::<String, _>("phoneNumber"));
                }
                obj
            })
            .collect(),
    ))
}

async fn get_user(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_self_or_admin(&user, &id)?;
    let uid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT * FROM users WHERE id = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("User not found".into()))?;
    Ok(Json(user_detail_json(&row, is_portal_admin(&user))))
}

async fn get_user_stats(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    assert_self_or_admin(&user, &id)?;
    let uid = Uuid::parse_str(&id)?;
    let bookings = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) FROM bookings WHERE "customerId" = $1 OR "operatorId" = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "totalBookings": bookings })))
}

async fn update_profile(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    assert_self_or_admin(&user, &id)?;
    let uid = Uuid::parse_str(&id)?;
    if let Some(name) = body.get("name").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE users SET name = $1 WHERE id = $2"#)
            .bind(name)
            .bind(uid)
            .execute(&state.db)
            .await?;
    }
    if is_portal_admin(&user) {
        if let Some(role) = body.get("role").and_then(|v| v.as_str()) {
            sqlx::query(r#"UPDATE users SET role = $1 WHERE id = $2"#)
                .bind(role)
                .bind(uid)
                .execute(&state.db)
                .await?;
        }
    }
    get_user(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct FcmBody {
    token: String,
}

async fn update_fcm_token(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<FcmBody>,
) -> AppResult<Json<Value>> {
    if user.user_id != id && !is_portal_admin(&user) {
        return Err(AppError::Forbidden("You can only update your own device token".into()));
    }
    let uid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE users SET "fcmToken" = $1 WHERE id = $2"#)
        .bind(&body.token)
        .bind(uid)
        .execute(&state.db)
        .await?;
    state.redis.cache_fcm_token(&id, &body.token).await?;
    Ok(Json(json!({ "message": "Updated" })))
}

#[derive(Deserialize)]
struct StatusBody {
    status: String,
}

async fn update_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<StatusBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "users")?;
    let uid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE users SET "approvalStatus" = $1 WHERE id = $2"#)
        .bind(&body.status)
        .bind(uid)
        .execute(&state.db)
        .await?;
    get_user(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct VerifyBody {
    isVerified: bool,
}

async fn verify_user(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<VerifyBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "users")?;
    let uid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE users SET "isVerified" = $1 WHERE id = $2"#)
        .bind(body.isVerified)
        .bind(uid)
        .execute(&state.db)
        .await?;
    get_user(State(state), user, Path(id)).await
}

async fn update_skill_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(skill_id): Path<String>,
    Json(body): Json<StatusBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "verifications")?;
    let sid = Uuid::parse_str(&skill_id)?;
    sqlx::query(r#"UPDATE professional_skills SET status = $1 WHERE id = $2"#)
        .bind(&body.status)
        .bind(sid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Updated" })))
}

fn user_list_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "phoneNumber": row.get::<String, _>("phoneNumber"),
        "name": row.get::<Option<String>, _>("name"),
        "role": row.get::<String, _>("role"),
        "isVerified": row.get::<bool, _>("isVerified"),
        "hasWorkerProfile": row.get::<bool, _>("hasWorkerProfile"),
        "approvalStatus": row.get::<String, _>("approvalStatus"),
    })
}

fn user_detail_json(row: &sqlx::postgres::PgRow, admin: bool) -> Value {
    let mut obj = json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "name": row.get::<Option<String>, _>("name"),
        "role": row.get::<String, _>("role"),
        "isVerified": row.get::<bool, _>("isVerified"),
        "hasWorkerProfile": row.get::<bool, _>("hasWorkerProfile"),
        "profileImageUrl": row.get::<Option<String>, _>("profileImageUrl"),
        "approvalStatus": row.get::<String, _>("approvalStatus"),
    });
    if admin {
        obj["phoneNumber"] = json!(row.get::<String, _>("phoneNumber"));
    }
    obj
}
