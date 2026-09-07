use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(get_all))
        .route("/nearby", get(get_nearby))
        .route("/nearby-counts", get(get_nearby_counts))
        .route("/register", post(register))
        .route("/live-toggle", post(live_toggle))
        .route("/me/dashboard", get(get_my_dashboard))
        .route("/me", get(get_me))
        .route("/me/location", patch(update_location))
        .route("/me/languages", patch(set_languages))
        .route("/me/service-radius", patch(set_service_radius))
        .route("/me/active-skills", patch(set_active_skills))
        .route("/me/pay-period-fee", post(pay_period_fee))
        .route("/me/strikes", get(get_my_strikes))
        .route("/me/strikes/{strike_id}/appeal", post(appeal_strike))
        .route("/admin/verification-queue", get(verification_queue))
        .route("/{id}/packages", get(get_packages))
        .route("/{id}", get(get_by_id))
}

async fn get_all(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(
        r#"SELECT w.*, u.name, u."profileImageUrl" FROM worker_profiles w JOIN users u ON u.id = w."userId" WHERE w."isLive" = true"#,
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_json).collect()))
}

#[derive(Deserialize)]
struct NearbyQuery {
    skill: String,
    lat: String,
    lng: String,
}

async fn get_nearby(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<NearbyQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let _lat = q.lat.parse::<f64>().unwrap_or(0.0);
    let _lng = q.lng.parse::<f64>().unwrap_or(0.0);
    let rows = sqlx::query(
        r#"SELECT w.*, u.name FROM worker_profiles w JOIN users u ON u.id = w."userId" WHERE w."isLive" = true AND $1 = ANY(w.skills)"#,
    )
    .bind(&q.skill)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_json).collect()))
}

#[derive(Deserialize)]
struct CountsQuery {
    lat: String,
    lng: String,
}

async fn get_nearby_counts(
    State(_state): State<AppState>,
    Query(_q): Query<CountsQuery>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "counts": {} })))
}

async fn get_my_dashboard(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile = sqlx::query(r#"SELECT * FROM worker_profiles WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?;
    let credits = sqlx::query_scalar::<_, i32>(r#"SELECT balance FROM job_credits WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or(0);
    Ok(Json(json!({
        "profile": profile.map(|p| worker_json(&p)),
        "jobCredits": credits,
        "isLive": profile.map(|p| p.get::<bool, _>("isLive")).unwrap_or(false),
    })))
}

async fn get_me(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let row = sqlx::query(r#"SELECT * FROM worker_profiles WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?;
    if let Some(r) = row {
        Ok(Json(json!({ "registered": true, "profile": worker_json(&r) })))
    } else {
        Ok(Json(json!({ "registered": false })))
    }
}

async fn register(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let skills = body.get("skills").cloned().unwrap_or(json!([]));
    sqlx::query(
        r#"INSERT INTO worker_profiles (id, "userId", skills, "hourlyRate", "serviceRadiusKm", "verificationStatus")
           VALUES ($1, $2, $3, $4, $5, 'PENDING')
           ON CONFLICT ("userId") DO UPDATE SET skills = $3"#,
    )
    .bind(id)
    .bind(uid)
    .bind(skills)
    .bind(body.get("hourlyRate").and_then(|v| v.as_f64()).unwrap_or(0.0))
    .bind(body.get("serviceRadiusKm").and_then(|v| v.as_f64()).unwrap_or(5.0))
    .execute(&state.db)
    .await?;
    sqlx::query(r#"UPDATE users SET "hasWorkerProfile" = true WHERE id = $1"#)
        .bind(uid)
        .execute(&state.db)
        .await?;
    get_me(State(state), user).await
}

#[derive(Deserialize)]
struct LiveToggleBody {
    lat: Option<f64>,
    lng: Option<f64>,
    active: Option<bool>,
}

async fn live_toggle(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<LiveToggleBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let active = body.active.unwrap_or(true);
    sqlx::query(
        r#"UPDATE worker_profiles SET "isLive" = $1, lat = COALESCE($2, lat), lng = COALESCE($3, lng) WHERE "userId" = $4"#,
    )
    .bind(active)
    .bind(body.lat)
    .bind(body.lng)
    .bind(uid)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "isActive": active })))
}

async fn set_languages(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    sqlx::query(r#"UPDATE worker_profiles SET languages = $1 WHERE "userId" = $2"#)
        .bind(body.get("languages").cloned().unwrap_or(json!([])))
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Updated" })))
}

#[derive(Deserialize)]
struct RadiusBody {
    serviceRadiusKm: f64,
}

async fn set_service_radius(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<RadiusBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    sqlx::query(r#"UPDATE worker_profiles SET "serviceRadiusKm" = $1 WHERE "userId" = $2"#)
        .bind(body.serviceRadiusKm)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "serviceRadiusKm": body.serviceRadiusKm })))
}

async fn set_active_skills(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    sqlx::query(r#"UPDATE worker_profiles SET "activeSkills" = $1 WHERE "userId" = $2"#)
        .bind(body.get("skills").cloned().unwrap_or(json!([])))
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Updated" })))
}

async fn pay_period_fee(
    State(_state): State<AppState>,
    _user: AuthUser,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "message": "Use Razorpay period-fee checkout" })))
}

async fn get_my_strikes(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let count = sqlx::query_scalar::<_, i32>(
        r#"SELECT COUNT(*)::int FROM worker_strikes WHERE "userId" = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "strikeCount": count, "suspended": false, "threshold": 3, "strikes": [] })))
}

#[derive(Deserialize)]
struct AppealBody {
    message: String,
}

async fn appeal_strike(
    State(_state): State<AppState>,
    _user: AuthUser,
    Path(_strike_id): Path<String>,
    Json(_body): Json<AppealBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "message": "Appeal submitted" })))
}

async fn get_packages(
    State(_state): State<AppState>,
    Path(_id): Path<String>,
) -> AppResult<Json<Vec<Value>>> {
    Ok(Json(vec![]))
}

#[derive(Deserialize)]
struct LocationBody {
    lat: f64,
    lng: f64,
}

async fn update_location(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<LocationBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    sqlx::query(r#"UPDATE worker_profiles SET lat = $1, lng = $2, "lastLocationAt" = NOW() WHERE "userId" = $3"#)
        .bind(body.lat)
        .bind(body.lng)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Location updated" })))
}

async fn verification_queue(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Value>>> {
    require_admin_page(&user, "verifications")?;
    let rows = sqlx::query(
        r#"SELECT w.*, u.name, u."phoneNumber" FROM worker_profiles w JOIN users u ON u.id = w."userId" WHERE w."verificationStatus" = 'PENDING'"#,
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_json).collect()))
}

async fn get_by_id(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT w.*, u.name, u."profileImageUrl" FROM worker_profiles w JOIN users u ON u.id = w."userId" WHERE w."userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Worker not found".into()))?;
    Ok(Json(worker_json(&row)))
}

fn worker_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "userId": row.try_get::<Uuid, _>("userId").map(|u| u.to_string()),
        "skills": row.try_get::<serde_json::Value, _>("skills"),
        "hourlyRate": row.try_get::<rust_decimal::Decimal, _>("hourlyRate"),
        "isLive": row.try_get::<bool, _>("isLive"),
        "verificationStatus": row.try_get::<String, _>("verificationStatus"),
        "lat": row.try_get::<Option<f64>, _>("lat"),
        "lng": row.try_get::<Option<f64>, _>("lng"),
        "name": row.try_get::<Option<String>, _>("name"),
    })
}
