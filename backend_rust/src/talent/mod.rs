use axum::{
    extract::State,
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::PROFESSIONAL_SKILL_COLS;
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

fn parse_list(raw: Option<String>) -> Vec<String> {
    raw.map(|s| {
        s.split(',')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect()
    })
    .unwrap_or_default()
}

fn list_to_db(items: &[String]) -> String {
    items.join(",")
}

async fn ensure_talent_profile(state: &AppState, user_id: Uuid) -> AppResult<Uuid> {
    let existing = sqlx::query_scalar::<_, Uuid>(
        r#"SELECT id FROM talent_profiles WHERE "userId" = $1"#,
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO talent_profiles (id, "userId", "jobAlertsEnabled") VALUES ($1, $2, true)"#,
    )
    .bind(id)
    .bind(user_id)
    .execute(&state.db)
    .await?;
    Ok(id)
}

async fn load_profile(state: &AppState, user_id: Uuid) -> AppResult<Value> {
    let profile_id = ensure_talent_profile(state, user_id).await?;
    let row = sqlx::query(
        r#"SELECT tp.id, tp."userId", tp."photoUrl", tp.certificates, tp.experience, tp."hourlyRate",
                  tp."jobAlertsEnabled", tp."savedJobIds",
                  u.name, u."approvalStatus"::text AS "approvalStatus"
           FROM talent_profiles tp
           JOIN users u ON u.id = tp."userId"
           WHERE tp."userId" = $1"#,
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;

    let skills = sqlx::query(&format!(
        r#"SELECT {PROFESSIONAL_SKILL_COLS} FROM professional_skills WHERE "talentProfileId" = $1 ORDER BY "createdAt""#
    ))
    .bind(profile_id)
    .fetch_all(&state.db)
    .await?;

    Ok(json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "photoUrl": row.get::<Option<String>, _>("photoUrl"),
        "certificates": parse_list(row.try_get::<Option<String>, _>("certificates").ok().flatten()),
        "experience": row.get::<Option<String>, _>("experience"),
        "hourlyRate": row.try_get::<Option<f64>, _>("hourlyRate").ok().flatten(),
        "jobAlertsEnabled": row.get::<bool, _>("jobAlertsEnabled"),
        "savedJobIds": parse_list(row.try_get::<Option<String>, _>("savedJobIds").ok().flatten()),
        "professionalSkills": skills.iter().map(skill_json).collect::<Vec<_>>(),
        "user": {
            "name": row.get::<Option<String>, _>("name"),
            "approvalStatus": row.get::<String, _>("approvalStatus"),
        },
    }))
}

async fn get_profile(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    Ok(Json(load_profile(&state, uid).await?))
}

async fn update_profile(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile_id = ensure_talent_profile(&state, uid).await?;

    if let Some(photo) = body.get("photoUrl").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE talent_profiles SET "photoUrl" = $1 WHERE id = $2"#)
            .bind(photo)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(certs) = body.get("certificates").and_then(|v| v.as_array()) {
        let cert_list: Vec<String> = certs
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect();
        sqlx::query(r#"UPDATE talent_profiles SET certificates = $1 WHERE id = $2"#)
            .bind(list_to_db(&cert_list))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(exp) = body.get("experience").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE talent_profiles SET experience = $1 WHERE id = $2"#)
            .bind(exp)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    Ok(Json(load_profile(&state, uid).await?))
}

async fn add_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile_id = ensure_talent_profile(&state, uid).await?;
    let skill_name = body.get("skillName").and_then(|v| v.as_str()).unwrap_or("");
    let rate = body.get("rate").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let bio = body.get("bio").and_then(|v| v.as_str()).unwrap_or("");
    let rate_chart = body.get("rateChart").cloned().unwrap_or(json!({}));

    let existing_id = sqlx::query_scalar::<_, Uuid>(
        r#"SELECT id FROM professional_skills WHERE "talentProfileId" = $1 AND name = $2"#,
    )
    .bind(profile_id)
    .bind(skill_name)
    .fetch_optional(&state.db)
    .await?;

    let skill_id = if let Some(id) = existing_id {
        sqlx::query(
            r#"UPDATE professional_skills SET "hourlyRate" = $1, bio = $2, "rateChart" = $3, status = 'PENDING' WHERE id = $4"#,
        )
        .bind(rate)
        .bind(bio)
        .bind(rate_chart)
        .bind(id)
        .execute(&state.db)
        .await?;
        id
    } else {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO professional_skills (id, "talentProfileId", name, "hourlyRate", bio, "rateChart", status)
               VALUES ($1, $2, $3, $4, $5, $6, 'PENDING')"#,
        )
        .bind(id)
        .bind(profile_id)
        .bind(skill_name)
        .bind(rate)
        .bind(bio)
        .bind(rate_chart)
        .execute(&state.db)
        .await?;
        id
    };

    let row = sqlx::query(&format!(
        r#"SELECT {PROFESSIONAL_SKILL_COLS} FROM professional_skills WHERE id = $1"#
    ))
    .bind(skill_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(skill_json(&row)))
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
    let profile_id = ensure_talent_profile(&state, uid).await?;
    let sid = Uuid::parse_str(&body.skillId)?;
    sqlx::query(
        r#"DELETE FROM professional_skills WHERE id = $1 AND "talentProfileId" = $2"#,
    )
    .bind(sid)
    .bind(profile_id)
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
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ToggleJobBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile_id = ensure_talent_profile(&state, uid).await?;
    let current = sqlx::query_scalar::<_, Option<String>>(
        r#"SELECT "savedJobIds" FROM talent_profiles WHERE id = $1"#,
    )
    .bind(profile_id)
    .fetch_one(&state.db)
    .await?;
    let mut saved = parse_list(current);
    if saved.iter().any(|id| id == &body.jobId) {
        saved.retain(|id| id != &body.jobId);
    } else {
        saved.push(body.jobId.clone());
    }
    sqlx::query(r#"UPDATE talent_profiles SET "savedJobIds" = $1 WHERE id = $2"#)
        .bind(list_to_db(&saved))
        .bind(profile_id)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "savedJobIds": saved })))
}

async fn verification_status(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let row = sqlx::query(
        r#"SELECT "verificationStatus"::text AS "verificationStatus", "maskedAadhaar"
           FROM worker_profiles WHERE "userId" = $1"#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?;
    if let Some(r) = row {
        let status = r.get::<String, _>("verificationStatus");
        Ok(Json(json!({
            "status": status,
            "verified": status == "VERIFIED",
            "maskedAadhaar": r.get::<Option<String>, _>("maskedAadhaar"),
        })))
    } else {
        Ok(Json(json!({ "status": "NOT_STARTED", "verified": false })))
    }
}

// Automated KYC is unavailable until this runtime verifies a real provider response.
// Manual document review remains a separate admin workflow; never mint VERIFIED here.
async fn verification_initiate(_user: AuthUser) -> Json<Value> {
    Json(json!({
        "status": "UNAVAILABLE", "verified": false, "needsApiKey": true,
        "provider": "AADHAAR",
        "message": "Automated identity verification is unavailable. Use document review from your professional profile."
    }))
}

fn automated_verification_unavailable() -> AppError {
    AppError::ServiceUnavailable("Automated identity verification is unavailable. Use document review from your professional profile.".into())
}

async fn aadhaar_generate_otp(_user: AuthUser) -> AppResult<Json<Value>> {
    Err(automated_verification_unavailable())
}

async fn aadhaar_submit_otp(_user: AuthUser) -> AppResult<Json<Value>> {
    Err(automated_verification_unavailable())
}

fn skill_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "name": row.get::<String, _>("name"),
        "hourlyRate": row.try_get::<f64, _>("hourlyRate").ok(),
        "bio": row.get::<Option<String>, _>("bio"),
        "status": row.get::<String, _>("status"),
        "rateChart": row.try_get::<serde_json::Value, _>("rateChart").ok(),
    })
}
