use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use chrono::{Datelike, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::WORKER_PROFILE_COLS;
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

fn parse_skills(raw: Option<String>) -> Vec<String> {
    raw.map(|s| {
        s.split(',')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect()
    })
    .unwrap_or_default()
}

fn skills_to_db(skills: &[String]) -> String {
    skills.join(",")
}

fn ist_today() -> String {
    let now = Utc::now() + chrono::Duration::hours(5) + chrono::Duration::minutes(30);
    format!("{:04}-{:02}-{:02}", now.year(), now.month(), now.day())
}

async fn load_profile(state: &AppState, user_id: Uuid) -> AppResult<Option<sqlx::postgres::PgRow>> {
    sqlx::query(&format!(
        r#"SELECT {WORKER_PROFILE_COLS} FROM worker_profiles WHERE "userId" = $1"#
    ))
    .bind(user_id)
    .fetch_optional(&state.db)
    .await
    .map_err(Into::into)
}

async fn ensure_profile(state: &AppState, user_id: Uuid) -> AppResult<sqlx::postgres::PgRow> {
    if let Some(row) = load_profile(state, user_id).await? {
        return Ok(row);
    }

    // Lazy-create from talent professional skills (Earn Hourly path).
    let talent_skills = sqlx::query(
        r#"SELECT ps.name
           FROM professional_skills ps
           JOIN talent_profiles tp ON tp.id = ps."talentProfileId"
           WHERE tp."userId" = $1"#,
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await?;

    if talent_skills.is_empty() {
        return Err(AppError::NotFound("Worker profile not found".into()));
    }

    let skills: Vec<String> = talent_skills
        .iter()
        .filter_map(|r| r.try_get::<String, _>("name").ok())
        .collect();
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO worker_profiles (id, "userId", skills, "activeSkills", "hourlyRate", "verificationStatus", "isActive")
           VALUES ($1, $2, $3, $3, 0, 'PENDING', false)"#,
    )
    .bind(id)
    .bind(user_id)
    .bind(skills_to_db(&skills))
    .execute(&state.db)
    .await?;
    sqlx::query(r#"UPDATE users SET "hasWorkerProfile" = true WHERE id = $1"#)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    load_profile(state, user_id)
        .await?
        .ok_or_else(|| AppError::NotFound("Worker profile not found".into()))
}

async fn job_credits(state: &AppState, user_id: Uuid) -> AppResult<i32> {
    Ok(
        sqlx::query_scalar::<_, i32>(r#"SELECT balance FROM job_credits WHERE "userId" = $1"#)
            .bind(user_id)
            .fetch_optional(&state.db)
            .await?
            .unwrap_or(0),
    )
}

async fn get_all(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"SELECT w.id, w."userId", w.skills, w."hourlyRate", w."isActive", w.rating, w."completedJobs",
                  w."reviewCount", w.bio, w.title, u.name, u."profileImageUrl"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."isActive" = true AND u."approvalStatus"::text = 'APPROVED'"#,
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(
        rows.iter()
            .filter_map(|r| {
                let worker_uid = r.try_get::<Uuid, _>("userId").ok();
                if worker_uid == Some(uid) {
                    return None;
                }
                Some(worker_list_json(r))
            })
            .collect(),
    ))
}

#[derive(Deserialize)]
struct NearbyQuery {
    skill: String,
    lat: String,
    lng: String,
}

async fn get_nearby(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<NearbyQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(
        r#"SELECT w.id, w.skills, w."hourlyRate", w."isActive", w.rating, w."completedJobs",
                  w."reviewCount", w.bio, w.title, u.name, u."profileImageUrl"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."isActive" = true
             AND position(lower($1) in lower(w.skills)) > 0"#,
    )
    .bind(&q.skill)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_list_json).collect()))
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
    Ok(Json(json!({})))
}

async fn get_my_dashboard(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile = ensure_profile(&state, uid).await?;
    let credits = job_credits(&state, uid).await?;

    let skills = parse_skills(profile.try_get::<Option<String>, _>("skills").ok().flatten());
    let active_skills =
        parse_skills(profile.try_get::<Option<String>, _>("activeSkills").ok().flatten());
    let is_active = profile.get::<bool, _>("isActive");
    let verification = profile.get::<String, _>("verificationStatus");
    let rating = profile
        .try_get::<rust_decimal::Decimal, _>("rating")
        .ok()
        .unwrap_or_default();
    let service_radius = profile.get::<i32, _>("serviceRadiusKm");
    let jobs_since_payment = profile.get::<i32, _>("jobsSincePayment");

    let completed = sqlx::query(
        r#"SELECT id, skill, amount, "totalAmount", "updatedAt", u.name AS "customerName"
           FROM bookings b
           LEFT JOIN users u ON u.id = b."customerId"
           WHERE b."operatorId" = $1 AND b.status::text = 'COMPLETED'
           ORDER BY b."updatedAt" DESC LIMIT 200"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;

    let mut total = 0.0;
    let mut today = 0.0;
    let mut this_week = 0.0;
    let start_of_day = ist_start_of_day();
    let start_of_week = start_of_day - chrono::Duration::days(6);

    let recent: Vec<Value> = completed
        .iter()
        .map(|r| {
            let amt = r
                .try_get::<Option<rust_decimal::Decimal>, _>("totalAmount")
                .ok()
                .flatten()
                .or_else(|| r.try_get::<Option<rust_decimal::Decimal>, _>("amount").ok().flatten())
                .map(|d| d.to_string().parse::<f64>().unwrap_or(0.0))
                .unwrap_or(0.0);
            let done_at = r
                .try_get::<chrono::DateTime<Utc>, _>("updatedAt")
                .ok()
                .unwrap_or_else(Utc::now);
            total += amt;
            if done_at >= start_of_day {
                today += amt;
            }
            if done_at >= start_of_week {
                this_week += amt;
            }
            json!({
                "id": r.get::<Uuid, _>("id").to_string(),
                "skill": r.try_get::<Option<String>, _>("skill").ok().flatten().unwrap_or_else(|| "Service".into()),
                "amount": amt,
                "customerName": r.try_get::<Option<String>, _>("customerName").ok().flatten().unwrap_or_else(|| "Customer".into()),
                "completedAt": done_at,
            })
        })
        .take(10)
        .collect();

    Ok(Json(json!({
        "skills": skills,
        "activeSkills": active_skills,
        "isActive": is_active,
        "verificationStatus": verification,
        "rating": rating,
        "serviceRadiusKm": service_radius,
        "jobCredits": credits,
        "feeModel": {
            "enabled": false,
            "jobsIncluded": 0,
            "jobsUsed": jobs_since_payment,
            "fee": 0,
            "paymentDue": false,
        },
        "earnings": {
            "total": (total * 100.0).round() / 100.0,
            "today": (today * 100.0).round() / 100.0,
            "thisWeek": (this_week * 100.0).round() / 100.0,
            "jobsCompleted": completed.len(),
            "recent": recent,
        },
    })))
}

fn ist_start_of_day() -> chrono::DateTime<Utc> {
    let now_ist = Utc::now() + chrono::Duration::hours(5) + chrono::Duration::minutes(30);
    let y = now_ist.year();
    let m = now_ist.month();
    let d = now_ist.day();
    chrono::DateTime::parse_from_rfc3339(&format!("{:04}-{:02}-{:02}T00:00:00+05:30", y, m, d))
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

async fn get_me(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let row = load_profile(&state, uid).await?;
    if let Some(r) = row {
        Ok(Json(my_profile_json(&r)))
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
    let skills: Vec<String> = body
        .get("skills")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|s| s.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    let hourly_rate = body.get("hourlyRate").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let bio = body.get("bio").and_then(|v| v.as_str());
    let title = body.get("title").and_then(|v| v.as_str());

    let existing = load_profile(&state, uid).await?;
    if let Some(_) = existing {
        sqlx::query(
            r#"UPDATE worker_profiles SET skills = $1, "hourlyRate" = $2, bio = COALESCE($3, bio), title = COALESCE($4, title) WHERE "userId" = $5"#,
        )
        .bind(skills_to_db(&skills))
        .bind(hourly_rate)
        .bind(bio)
        .bind(title)
        .bind(uid)
        .execute(&state.db)
        .await?;
    } else {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO worker_profiles (id, "userId", skills, "hourlyRate", bio, title, "verificationStatus", "isActive")
               VALUES ($1, $2, $3, $4, $5, $6, 'PENDING', false)"#,
        )
        .bind(id)
        .bind(uid)
        .bind(skills_to_db(&skills))
        .bind(hourly_rate)
        .bind(bio)
        .bind(title)
        .execute(&state.db)
        .await?;
    }
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
    let profile = ensure_profile(&state, uid).await?;
    let current = profile.get::<bool, _>("isActive");
    let target = body.active.unwrap_or(!current);

    if target == current {
        return Ok(Json(json!({
            "isActive": current,
            "message": if current {
                "You are now LIVE on the map and accepting jobs."
            } else {
                "You are now OFFLINE. Customers cannot dispatch you instantly."
            },
        })));
    }

    if target {
        let verification = profile.get::<String, _>("verificationStatus");
        if verification != "VERIFIED" {
            return Err(AppError::BadRequest(
                "Your profile is not verified yet. Please complete the verification process to go live.".into(),
            ));
        }
        let credits = job_credits(&state, uid).await?;
        if credits <= 0 {
            return Err(AppError::BadRequest(
                "You need job credits to go live and accept new bookings. Please buy a job pack to continue.".into(),
            ));
        }
        let has_coords = body.lat.is_some() && body.lng.is_some()
            || (profile.try_get::<Option<rust_decimal::Decimal>, _>("lastLat").ok().flatten().is_some()
                && profile.try_get::<Option<rust_decimal::Decimal>, _>("lastLng").ok().flatten().is_some());
        if !has_coords {
            return Err(AppError::BadRequest(
                "Location is required to go live — customers are matched to pros by live GPS. Enable location and try again.".into(),
            ));
        }
    }

    let today = ist_today();
    let toggle_date = profile
        .try_get::<Option<chrono::NaiveDate>, _>("goLiveToggleDate")
        .ok()
        .flatten()
        .map(|d| d.to_string());
    let mut count = profile.get::<i32, _>("goLiveToggleCountToday");
    if toggle_date.as_deref() != Some(&today) {
        count = 0;
    }
    if target {
        count += 1;
    }

    sqlx::query(
        r#"UPDATE worker_profiles
           SET "isActive" = $1,
               "lastLat" = COALESCE($2, "lastLat"),
               "lastLng" = COALESCE($3, "lastLng"),
               "goLiveToggleDate" = $4::date,
               "goLiveToggleCountToday" = $5
           WHERE "userId" = $6"#,
    )
    .bind(target)
    .bind(body.lat)
    .bind(body.lng)
    .bind(&today)
    .bind(count)
    .bind(uid)
    .execute(&state.db)
    .await?;

    Ok(Json(json!({
        "isActive": target,
        "message": if target {
            "You are now LIVE on the map and accepting jobs."
        } else {
            "You are now OFFLINE. Customers cannot dispatch you instantly."
        },
    })))
}

async fn set_languages(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let langs: Vec<String> = body
        .get("languages")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|s| s.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    sqlx::query(r#"UPDATE worker_profiles SET languages = $1 WHERE "userId" = $2"#)
        .bind(skills_to_db(&langs))
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
    let radius = body.serviceRadiusKm.clamp(1.0, 50.0) as i32;
    sqlx::query(r#"UPDATE worker_profiles SET "serviceRadiusKm" = $1 WHERE "userId" = $2"#)
        .bind(radius)
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "serviceRadiusKm": radius })))
}

async fn set_active_skills(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let profile = ensure_profile(&state, uid).await?;
    let allowed = parse_skills(profile.try_get::<Option<String>, _>("skills").ok().flatten());
    let requested: Vec<String> = body
        .get("skills")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|s| s.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    let active = if requested.is_empty() {
        vec![]
    } else {
        requested
            .into_iter()
            .filter(|s| allowed.contains(s))
            .collect()
    };
    sqlx::query(r#"UPDATE worker_profiles SET "activeSkills" = $1 WHERE "userId" = $2"#)
        .bind(skills_to_db(&active))
        .bind(uid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "skills": allowed, "activeSkills": active })))
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
    sqlx::query(r#"UPDATE worker_profiles SET "lastLat" = $1, "lastLng" = $2 WHERE "userId" = $3"#)
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
    let rows = sqlx::query(&format!(
        r#"SELECT {WORKER_PROFILE_COLS}, u.name, u."phoneNumber"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."verificationStatus"::text = 'PENDING'"#
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_json).collect()))
}

async fn get_by_id(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {WORKER_PROFILE_COLS}, u.name, u."profileImageUrl"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."userId" = $1"#
    ))
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Worker not found".into()))?;
    Ok(Json(worker_json(&row)))
}

fn my_profile_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "registered": true,
        "id": row.get::<Uuid, _>("id").to_string(),
        "skills": parse_skills(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "hourlyRate": row.try_get::<rust_decimal::Decimal, _>("hourlyRate").ok(),
        "bio": row.get::<Option<String>, _>("bio"),
        "title": row.get::<Option<String>, _>("title"),
        "isActive": row.get::<bool, _>("isActive"),
        "verificationStatus": row.get::<String, _>("verificationStatus"),
        "maskedAadhaar": row.try_get::<Option<String>, _>("maskedAadhaar").ok().flatten(),
        "isFirstJobDone": row.try_get::<bool, _>("isFirstJobDone").ok().unwrap_or(false),
        "languages": parse_skills(row.try_get::<Option<String>, _>("languages").ok().flatten()),
        "serviceRadiusKm": row.get::<i32, _>("serviceRadiusKm"),
    })
}

fn worker_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "userId": row.try_get::<Uuid, _>("userId").ok().map(|u| u.to_string()),
        "skills": parse_skills(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "hourlyRate": row.try_get::<rust_decimal::Decimal, _>("hourlyRate").ok(),
        "isActive": row.try_get::<bool, _>("isActive").ok(),
        "verificationStatus": row.try_get::<String, _>("verificationStatus").ok(),
        "lastLat": row.try_get::<Option<rust_decimal::Decimal>, _>("lastLat").ok().flatten(),
        "lastLng": row.try_get::<Option<rust_decimal::Decimal>, _>("lastLng").ok().flatten(),
        "name": row.try_get::<Option<String>, _>("name").ok().flatten(),
    })
}

fn worker_list_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "name": row.try_get::<Option<String>, _>("name").ok().flatten().unwrap_or_default(),
        "title": row.try_get::<Option<String>, _>("title").ok().flatten().unwrap_or_default(),
        "bio": row.try_get::<Option<String>, _>("bio").ok().flatten().unwrap_or_default(),
        "image_url": row.try_get::<Option<String>, _>("profileImageUrl").ok().flatten(),
        "rating": row.try_get::<rust_decimal::Decimal, _>("rating").ok().unwrap_or_default(),
        "completed_jobs": row.get::<i32, _>("completedJobs"),
        "review_count": row.get::<i32, _>("reviewCount"),
        "hourly_rate": row.try_get::<rust_decimal::Decimal, _>("hourlyRate").ok().unwrap_or_default(),
        "skills": parse_skills(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "availability_tags": [],
        "status": if row.get::<bool, _>("isActive") { "available" } else { "offline" },
    })
}
