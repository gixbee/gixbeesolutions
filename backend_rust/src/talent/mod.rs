use axum::{
    extract::{Path, State},
    routing::{get, patch, post},
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
        .route("/profile", get(get_profile).post(update_profile))
        .route("/skills", post(add_skill))
        .route("/skills/remove", post(remove_skill))
        .route("/alerts", patch(update_alerts))
        .route("/saved-jobs/toggle", post(toggle_saved_job))
        .route("/verification/status", get(verification_status))
        .route("/verification/initiate", post(verification_initiate))
        .route("/verification/generate-otp", post(aadhaar_generate_otp))
        .route("/verification/submit-otp", post(aadhaar_submit_otp))
}

async fn get_profile(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let row = sqlx::query(r#"SELECT * FROM talent_profiles WHERE "userId" = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await?;
    Ok(Json(row.map(|r| talent_json(&r)).unwrap_or(json!({ "registered": false }))))
}

async fn update_profile(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO talent_profiles (id, "userId", headline, experience, "jobAlertsEnabled")
           VALUES ($1, $2, $3, $4, true)
           ON CONFLICT ("userId") DO UPDATE SET headline = $3, experience = $4"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("headline").and_then(|v| v.as_str()))
    .bind(body.get("experience").and_then(|v| v.as_i64()).unwrap_or(0))
    .execute(&state.db)
    .await?;
    get_profile(State(state), user).await
}

async fn add_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let skill = body.get("skillName").and_then(|v| v.as_str()).unwrap_or("");
    sqlx::query(
        r#"INSERT INTO professional_skills (id, "userId", skill, status) VALUES ($1, $2, $3, 'PENDING')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(skill)
    .execute(&state.db)
    .await?;
    Ok(Json(skill_json(
        &sqlx::query(r#"SELECT * FROM professional_skills WHERE id = $1"#)
            .bind(id)
            .fetch_one(&state.db)
            .await?,
    )))
}

#[derive(Deserialize)]
struct RemoveSkillBody {
    skillId: String,
}

async fn remove_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<RemoveSkillBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let sid = Uuid::parse_str(&body.skillId)?;
    sqlx::query(r#"DELETE FROM professional_skills WHERE id = $1 AND "userId" = $2"#)
        .bind(sid)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Removed" })))
}

#[derive(Deserialize)]
struct AlertsBody {
    enabled: bool,
}

async fn update_alerts(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<AlertsBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    sqlx::query(r#"UPDATE talent_profiles SET "jobAlertsEnabled" = $1 WHERE "userId" = $2"#)
        .bind(body.enabled)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "enabled": body.enabled })))
}

#[derive(Deserialize)]
struct ToggleJobBody {
    jobId: String,
}

async fn toggle_saved_job(
    State(_state): State<AppState>,
    _user: AuthUser,
    Json(body): Json<ToggleJobBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "jobId": body.jobId, "saved": true })))
}

async fn verification_status() -> Json<Value> {
    Json(json!({ "status": "NOT_STARTED" }))
}

async fn verification_initiate() -> Json<Value> {
    Json(json!({ "message": "Initiated" }))
}

#[derive(Deserialize)]
struct AadhaarOtpBody {
    aadhaarNumber: String,
}

async fn aadhaar_generate_otp(
    State(state): State<AppState>,
    user: AuthUser,
    Json(_body): Json<AadhaarOtpBody>,
) -> AppResult<Json<Value>> {
    if state.config.aadhaar_client_secret.is_none() {
        return Err(AppError::ServiceUnavailable("Aadhaar eKYC not configured".into()));
    }
    Ok(Json(json!({ "clientId": format!("dev-{}", user.user_id) })))
}

#[derive(Deserialize)]
struct AadhaarSubmitBody {
    clientId: String,
    otp: String,
}

async fn aadhaar_submit_otp(
    State(_state): State<AppState>,
    _user: AuthUser,
    Json(_body): Json<AadhaarSubmitBody>,
) -> AppResult<Json<Value>> {
    Ok(Json(json!({ "verified": true })))
}

fn talent_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "userId": row.get::<Uuid, _>("userId").to_string(),
        "headline": row.get::<Option<String>, _>("headline"),
        "experience": row.get::<i32, _>("experience"),
        "jobAlertsEnabled": row.get::<bool, _>("jobAlertsEnabled"),
    })
}

fn skill_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "skill": row.get::<String, _>("skill"),
        "status": row.get::<String, _>("status"),
    })
}
