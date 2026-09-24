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
        r#"INSERT INTO talent_profiles (id, "userId", "jobAlertsEnabled", "profileStatus")
           VALUES ($1, $2, true, 'INCOMPLETE')"#,
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
        r#"SELECT tp.id, tp."userId",
                  COALESCE(NULLIF(tp."photoUrl", ''), NULLIF(u."profileImageUrl", '')) AS "photoUrl",
                  tp.certificates, tp.experience, tp."hourlyRate",
                  tp."jobAlertsEnabled", tp."savedJobIds",
                  tp.skills, tp."preferredRoles", tp."preferredLocations", tp."expectedSalary",
                  tp."expectedSalaryPeriod", tp."employmentTypes", tp.education,
                  tp."currentStatus"::text AS "currentStatus",
                  tp.lat, tp.lng, tp."travelRadiusKm", tp.availability, tp."availableOn",
                  tp."profileStatus", tp."preferredWorkMode",
                  tp."positionIds", tp."specializationIds", tp."skillIds", tp."qualificationId",
                  tp."locationId", tp."addressText", tp."locationMatchStatus",
                  tp."resumeUrl", tp."resumeFileName", tp."resumeMimeType", tp."resumeUploadedAt",
                  u.name, u."profileImageUrl", u."approvalStatus"::text AS "approvalStatus"
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
        "skills": parse_list(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "preferredRoles": parse_list(row.try_get::<Option<String>, _>("preferredRoles").ok().flatten()),
        "preferredLocations": parse_list(row.try_get::<Option<String>, _>("preferredLocations").ok().flatten()),
        "expectedSalary": row.try_get::<Option<i32>, _>("expectedSalary").ok().flatten(),
        "expectedSalaryPeriod": row.try_get::<String, _>("expectedSalaryPeriod").unwrap_or_else(|_| "MONTHLY".into()),
        "employmentTypes": parse_list(row.try_get::<Option<String>, _>("employmentTypes").ok().flatten()),
        "education": parse_list(row.try_get::<Option<String>, _>("education").ok().flatten()),
        "currentStatus": row.try_get::<Option<String>, _>("currentStatus").ok().flatten(),
        "lat": row.try_get::<Option<f64>, _>("lat").ok().flatten(),
        "lng": row.try_get::<Option<f64>, _>("lng").ok().flatten(),
        "travelRadiusKm": row.try_get::<f64, _>("travelRadiusKm").unwrap_or(25.0),
        "availability": row.try_get::<String, _>("availability").unwrap_or_else(|_| "IMMEDIATE".into()),
        "availableOn": row.try_get::<Option<chrono::NaiveDate>, _>("availableOn").ok().flatten().map(|d| d.to_string()),
        "profileStatus": row.try_get::<String, _>("profileStatus").unwrap_or_else(|_| "ACTIVE".into()),
        "preferredWorkMode": row.try_get::<Option<String>, _>("preferredWorkMode").ok().flatten(),
        "positionIds": parse_list(row.try_get::<Option<String>, _>("positionIds").ok().flatten()),
        "specializationIds": parse_list(row.try_get::<Option<String>, _>("specializationIds").ok().flatten()),
        "skillIds": parse_list(row.try_get::<Option<String>, _>("skillIds").ok().flatten()),
        "qualificationId": row.try_get::<Option<String>, _>("qualificationId").ok().flatten(),
        "locationId": row.try_get::<Option<String>, _>("locationId").ok().flatten(),
        "addressText": row.try_get::<Option<String>, _>("addressText").ok().flatten(),
        "locationMatchStatus": row.try_get::<String, _>("locationMatchStatus").unwrap_or_else(|_| "UNRESOLVED".into()),
        "resumeUrl": row.try_get::<Option<String>, _>("resumeUrl").ok().flatten(),
        "resumeFileName": row.try_get::<Option<String>, _>("resumeFileName").ok().flatten(),
        "resumeMimeType": row.try_get::<Option<String>, _>("resumeMimeType").ok().flatten(),
        "resumeUploadedAt": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("resumeUploadedAt").ok().flatten().map(|d| d.to_rfc3339()),
        "professionalSkills": skills.iter().map(skill_json).collect::<Vec<_>>(),
        "user": {
            "name": row.get::<Option<String>, _>("name"),
            "profileImageUrl": row.get::<Option<String>, _>("profileImageUrl"),
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
    let catalogue_keys = [
        "positionIds",
        "specializationIds",
        "skillIds",
        "qualificationId",
        "locationId",
    ];
    if body
        .as_object()
        .is_some_and(|fields| catalogue_keys.iter().any(|key| fields.contains_key(*key)))
    {
        let current = sqlx::query(
            r#"SELECT "positionIds", "specializationIds", "skillIds", "qualificationId", "locationId"
               FROM talent_profiles WHERE id = $1"#,
        )
        .bind(profile_id)
        .fetch_one(&state.db)
        .await?;
        let previous = json!({
            "positionIds": crate::common::pg::string_list(&current, "positionIds"),
            "specializationIds": crate::common::pg::string_list(&current, "specializationIds"),
            "skillIds": crate::common::pg::string_list(&current, "skillIds"),
            "qualificationId": current.try_get::<Option<String>, _>("qualificationId").ok().flatten(),
            "locationId": current.try_get::<Option<String>, _>("locationId").ok().flatten(),
        });
        let mut merged = previous.clone();
        if let Some(fields) = body.as_object() {
            for key in catalogue_keys {
                if let Some(value) = fields.get(key) {
                    merged[key] = value.clone();
                }
            }
        }
        crate::matching::validate_merged_talent(&state, &merged, &previous).await?;
    }

    if let Some(photo) = body.get("photoUrl").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE talent_profiles SET "photoUrl" = $1 WHERE id = $2"#)
            .bind(photo)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
        sqlx::query(
            r#"UPDATE users SET "profileImageUrl" = $1, "updatedAt" = NOW() WHERE id = $2"#,
        )
        .bind(photo)
        .bind(uid)
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
    if let Some(ids) = string_array(body.get("positionIds")) {
        sqlx::query(r#"UPDATE talent_profiles SET "positionIds" = $1 WHERE id = $2"#)
            .bind(list_to_db(&ids)).bind(profile_id).execute(&state.db).await?;
    }
    if let Some(ids) = string_array(body.get("specializationIds")) {
        sqlx::query(r#"UPDATE talent_profiles SET "specializationIds" = $1 WHERE id = $2"#)
            .bind(list_to_db(&ids)).bind(profile_id).execute(&state.db).await?;
    }
    if let Some(ids) = string_array(body.get("skillIds")) {
        sqlx::query(r#"UPDATE talent_profiles SET "skillIds" = $1 WHERE id = $2"#)
            .bind(list_to_db(&ids)).bind(profile_id).execute(&state.db).await?;
    }
    if body.get("qualificationId").is_some() {
        let id = body.get("qualificationId").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
        sqlx::query(r#"UPDATE talent_profiles SET "qualificationId" = $1 WHERE id = $2"#)
            .bind(id).bind(profile_id).execute(&state.db).await?;
    }
    if body.get("locationId").is_some() {
        let id = body.get("locationId").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
        let status = if id.is_some() { "MAPPED" } else { "UNRESOLVED" };
        sqlx::query(r#"UPDATE talent_profiles SET "locationId" = $1, "locationMatchStatus" = $2 WHERE id = $3"#)
            .bind(id).bind(status).bind(profile_id).execute(&state.db).await?;
    }
    if let Some(address) = body.get("addressText").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE talent_profiles SET "addressText" = $1 WHERE id = $2"#)
            .bind(address).bind(profile_id).execute(&state.db).await?;
    }
    if let Some(roles) = string_array(body.get("preferredRoles")) {
        sqlx::query(r#"UPDATE talent_profiles SET "preferredRoles" = $1 WHERE id = $2"#)
            .bind(list_to_db(&roles))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(skills) = string_array(body.get("skills")) {
        sqlx::query(r#"UPDATE talent_profiles SET skills = $1 WHERE id = $2"#)
            .bind(list_to_db(&skills))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
        crate::match_engine::persist::sync_candidate_skills(&state, profile_id, &skills).await;
        let roles = string_array(body.get("preferredRoles")).unwrap_or_default();
        let text = crate::match_engine::embeddings::candidate_text(
            &roles,
            &skills,
            body.get("experience").and_then(|v| v.as_str()).unwrap_or(""),
        );
        crate::match_engine::persist::save_candidate_embedding(&state, profile_id, &text).await;
    }
    if let Some(places) = string_array(body.get("preferredLocations")) {
        sqlx::query(r#"UPDATE talent_profiles SET "preferredLocations" = $1 WHERE id = $2"#)
            .bind(list_to_db(&places))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(salary) = body.get("expectedSalary").and_then(|v| v.as_i64()) {
        sqlx::query(r#"UPDATE talent_profiles SET "expectedSalary" = $1 WHERE id = $2"#)
            .bind(salary as i32)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(status) = body.get("currentStatus").and_then(|v| v.as_str()) {
        if ["FINAL_YEAR", "GRADUATE", "EXPERIENCED"].contains(&status) {
            sqlx::query(
                r#"UPDATE talent_profiles SET "currentStatus" = $1::talent_profiles_currentstatus_enum WHERE id = $2"#,
            )
            .bind(status)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
        }
    }
    if body.get("lat").is_some() || body.get("lng").is_some() {
        sqlx::query(r#"UPDATE talent_profiles SET lat = $1, lng = $2 WHERE id = $3"#)
            .bind(body.get("lat").and_then(|v| v.as_f64()))
            .bind(body.get("lng").and_then(|v| v.as_f64()))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(radius) = body.get("travelRadiusKm").and_then(|v| v.as_f64()) {
        sqlx::query(r#"UPDATE talent_profiles SET "travelRadiusKm" = $1 WHERE id = $2"#)
            .bind(radius)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(mode) = body.get("preferredWorkMode").and_then(|v| v.as_str()) {
        let mode = mode.trim().to_ascii_uppercase();
        if !["ONSITE", "REMOTE", "HYBRID"].contains(&mode.as_str()) {
            return Err(AppError::BadRequest("Unsupported work preference".into()));
        }
        sqlx::query(r#"UPDATE talent_profiles SET "preferredWorkMode" = $1 WHERE id = $2"#)
            .bind(mode)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(period) = body.get("expectedSalaryPeriod").and_then(|v| v.as_str()) {
        let period = period.trim().to_ascii_uppercase();
        if !["HOURLY", "DAILY", "WEEKLY", "MONTHLY", "PER_JOB"].contains(&period.as_str()) {
            return Err(AppError::BadRequest("Unsupported salary period".into()));
        }
        sqlx::query(r#"UPDATE talent_profiles SET "expectedSalaryPeriod" = $1 WHERE id = $2"#)
            .bind(period)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(types) = string_array(body.get("employmentTypes")) {
        let allowed = ["FT", "PT", "INTERN", "CONTRACT", "GIG"];
        if types.iter().any(|code| !allowed.contains(&code.as_str())) {
            return Err(AppError::BadRequest("Unsupported employment type".into()));
        }
        sqlx::query(r#"UPDATE talent_profiles SET "employmentTypes" = $1 WHERE id = $2"#)
            .bind(list_to_db(&types))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(education) = string_array(body.get("education")) {
        sqlx::query(r#"UPDATE talent_profiles SET education = $1 WHERE id = $2"#)
            .bind(list_to_db(&education))
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if let Some(status) = body.get("profileStatus").and_then(|v| v.as_str()) {
        if !["ACTIVE", "PAUSED", "INCOMPLETE"].contains(&status) {
            return Err(AppError::BadRequest("Unsupported profile status".into()));
        }
        sqlx::query(r#"UPDATE talent_profiles SET "profileStatus" = $1 WHERE id = $2"#)
            .bind(status)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if body.get("availability").is_some() || body.get("availableOn").is_some() {
        let availability = body
            .get("availability")
            .and_then(|v| v.as_str())
            .unwrap_or("IMMEDIATE")
            .trim()
            .to_ascii_uppercase();
        if !["IMMEDIATE", "DAYS_7", "DAYS_15", "DAYS_30", "DAYS_60", "DAYS_90", "CUSTOM_DATE"]
            .contains(&availability.as_str())
        {
            return Err(AppError::BadRequest("Unsupported availability".into()));
        }
        let available_on = if availability == "CUSTOM_DATE" {
            let raw = body.get("availableOn").and_then(|v| v.as_str()).unwrap_or("");
            Some(
                chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d")
                    .map_err(|_| AppError::BadRequest("Choose the date you can join".into()))?,
            )
        } else {
            None
        };
        sqlx::query(r#"UPDATE talent_profiles SET availability = $1, "availableOn" = $2 WHERE id = $3"#)
            .bind(availability)
            .bind(available_on)
            .bind(profile_id)
            .execute(&state.db)
            .await?;
    }
    if body.get("resumeUrl").is_some()
        || body.get("resumeFileName").is_some()
        || body.get("resumeMimeType").is_some()
    {
        let url = body.get("resumeUrl").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
        let name = body.get("resumeFileName").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
        let mime = body.get("resumeMimeType").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
        let uploaded = if url.is_none() {
            None
        } else if let Some(raw) = body.get("resumeUploadedAt").and_then(|v| v.as_str()) {
            chrono::DateTime::parse_from_rfc3339(raw)
                .ok()
                .map(|value| value.with_timezone(&chrono::Utc))
        } else {
            Some(chrono::Utc::now())
        };
        sqlx::query(
            r#"UPDATE talent_profiles
               SET "resumeUrl" = $1, "resumeFileName" = $2, "resumeMimeType" = $3, "resumeUploadedAt" = $4
               WHERE id = $5"#,
        )
        .bind(url)
        .bind(name)
        .bind(mime)
        .bind(uploaded)
        .bind(profile_id)
        .execute(&state.db)
        .await?;
    }
    sqlx::query(r#"UPDATE talent_profiles SET "lastActiveAt" = NOW(), "updatedAt" = NOW() WHERE id = $1"#)
        .bind(profile_id)
        .execute(&state.db)
        .await?;
    Ok(Json(load_profile(&state, uid).await?))
}

fn string_array(value: Option<&Value>) -> Option<Vec<String>> {
    value.and_then(|v| v.as_array()).map(|items| {
        items
            .iter()
            .filter_map(|v| v.as_str().map(str::trim).filter(|s| !s.is_empty()).map(str::to_owned))
            .collect()
    })
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
