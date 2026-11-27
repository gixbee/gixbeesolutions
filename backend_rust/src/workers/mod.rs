use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use chrono::{Datelike, Utc};
use rust_decimal::prelude::ToPrimitive;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashSet;
use uuid::Uuid;

use crate::common::pg::{worker_profile_cols, WORKER_PROFILE_COLS};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::{require_admin_page, AuthUser};
use crate::state::AppState;

const MAX_DISPATCH_RADIUS_KM: f64 = 50.0;
const DEFAULT_SERVICE_RADIUS_KM: f64 = 10.0;
const MAX_NEARBY_CANDIDATES: usize = 40;
const MAX_BROADCAST_FANOUT: usize = 15;
const SUSPENSION_STRIKE_THRESHOLD: i32 = 3;
pub const REBROADCAST_RADIUS_STRETCH: f64 = 1.3;

pub struct DispatchWorker {
    pub id: String,
    pub distance_km: f64,
    pub rating: f64,
    pub languages: Vec<String>,
}

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
        .route("/admin/{user_id}/verification", patch(set_verification))
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

/// Registered pro (not a ghost shell) and not strike-suspended.
fn profile_is_registered_pro(profile: &sqlx::postgres::PgRow) -> bool {
    let skills = parse_skills(
        profile
            .try_get::<Option<String>, _>("skills")
            .ok()
            .flatten(),
    );
    let verification = profile.get::<String, _>("verificationStatus");
    if skills.is_empty() && verification == "PENDING" {
        return false;
    }
    if skills.is_empty() {
        return false;
    }
    let strike_count = profile.try_get::<i32, _>("strikeCount").unwrap_or(0);
    strike_count < SUSPENSION_STRIKE_THRESHOLD
}

/// Same gates as going live (except live GPS in this request).
fn profile_can_go_online(profile: &sqlx::postgres::PgRow, credits: i32) -> bool {
    if !profile_is_registered_pro(profile) {
        return false;
    }
    if profile.get::<String, _>("verificationStatus") != "VERIFIED" {
        return false;
    }
    let languages =
        parse_skills(profile.try_get::<Option<String>, _>("languages").ok().flatten());
    if languages.is_empty() {
        return false;
    }
    credits > 0
}

/// Show availability control: online workers can go offline; otherwise must pass go-live gates.
fn profile_show_availability_control(
    profile: &sqlx::postgres::PgRow,
    credits: i32,
    is_active: bool,
) -> bool {
    if is_active {
        return true;
    }
    profile_can_go_online(profile, credits)
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

fn parse_coords(lat: &str, lng: &str) -> AppResult<(f64, f64)> {
    let lat = lat
        .parse::<f64>()
        .map_err(|_| AppError::BadRequest("lat must be a number".into()))?;
    let lng = lng
        .parse::<f64>()
        .map_err(|_| AppError::BadRequest("lng must be a number".into()))?;
    if !lat.is_finite() || !lng.is_finite() {
        return Err(AppError::BadRequest("lat and lng are required".into()));
    }
    Ok((lat, lng))
}

fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let r = 6371.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lng = (lng2 - lng1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    r * c
}

fn decimal_f64(d: rust_decimal::Decimal) -> f64 {
    d.to_f64().unwrap_or(0.0)
}

fn dispatchable_skills(all_skills: &[String], active_skills: &[String]) -> Vec<String> {
    let active = active_skills
        .iter()
        .filter(|s| all_skills.iter().any(|a| a.eq_ignore_ascii_case(s)))
        .cloned()
        .collect::<Vec<_>>();
    if active.is_empty() {
        all_skills.to_vec()
    } else {
        active
    }
}

fn skill_matches(profile_skills: &[String], skill: &str) -> bool {
    let needle = skill.to_lowercase();
    profile_skills
        .iter()
        .any(|s| s.to_lowercase().contains(&needle) || needle.contains(&s.to_lowercase()))
}

async fn skill_worker_ids_from_db(state: &AppState, skill: &str) -> AppResult<Vec<String>> {
    let rows = sqlx::query(
        r#"SELECT w."userId", w.skills, w."activeSkills"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."isActive" = true
             AND u."approvalStatus"::text = 'APPROVED'"#,
    )
    .fetch_all(&state.db)
    .await?;
    Ok(rows
        .iter()
        .filter_map(|r| {
            let all = parse_skills(r.try_get::<Option<String>, _>("skills").ok().flatten());
            let active =
                parse_skills(r.try_get::<Option<String>, _>("activeSkills").ok().flatten());
            let dispatch = dispatchable_skills(&all, &active);
            if dispatch.iter().any(|s| s.eq_ignore_ascii_case(skill))
                || skill_matches(&all, skill)
            {
                r.try_get::<Uuid, _>("userId").ok().map(|u| u.to_string())
            } else {
                None
            }
        })
        .collect())
}

async fn load_nearby_for_dispatch(
    state: &AppState,
    requester_id: &str,
    skill: &str,
    lat: f64,
    lng: f64,
    radius_stretch: f64,
) -> AppResult<Vec<DispatchWorker>> {
    let skill = skill.trim();
    if skill.is_empty() {
        return Ok(vec![]);
    }

    let mut skill_ids = state.redis.get_worker_ids_by_skill(skill).await?;
    if skill_ids.is_empty() {
        skill_ids = skill_worker_ids_from_db(state, skill).await?;
    }
    if skill_ids.is_empty() {
        return Ok(vec![]);
    }

    let rejected: HashSet<String> = state
        .redis
        .get_rejected_workers_for_job(requester_id, skill)
        .await?
        .into_iter()
        .collect();

    let nearby_ids = state
        .redis
        .search_nearby_worker_ids(lat, lng, MAX_DISPATCH_RADIUS_KM)
        .await?;
    if let Some(ids) = nearby_ids {
        if !ids.is_empty() {
            let near_set: HashSet<String> = ids.into_iter().collect();
            let narrowed = skill_ids
                .iter()
                .filter(|id| near_set.contains(*id))
                .cloned()
                .collect::<Vec<_>>();
            if !narrowed.is_empty() {
                skill_ids = narrowed;
            }
        }
    }

    skill_ids.retain(|id| id != requester_id && !rejected.contains(id));
    if skill_ids.is_empty() {
        return Ok(vec![]);
    }

    let uuids: Vec<Uuid> = skill_ids
        .iter()
        .filter_map(|id| Uuid::parse_str(id).ok())
        .collect();
    if uuids.is_empty() {
        return Ok(vec![]);
    }

    let rows = sqlx::query(
        r#"SELECT w."userId", w.skills, w."activeSkills", w.languages, w.rating,
                  w."serviceRadiusKm", w."lastLat", w."lastLng"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."userId" = ANY($1)
             AND w."isActive" = true
             AND w."verificationStatus"::text = 'VERIFIED'
             AND u."approvalStatus"::text = 'APPROVED'"#,
    )
    .bind(&uuids)
    .fetch_all(&state.db)
    .await?;

    // Bound Redis fan-out: one MGET for status + one MGET for locations.
    const REDIS_BATCH: usize = 64;
    let worker_ids: Vec<String> = rows
        .iter()
        .map(|r| r.get::<Uuid, _>("userId").to_string())
        .collect();
    let mut status_by_id = std::collections::HashMap::new();
    let mut location_by_id = std::collections::HashMap::new();
    for chunk in worker_ids.chunks(REDIS_BATCH) {
        let statuses = state.redis.mget_worker_statuses(chunk).await?;
        status_by_id.extend(statuses);
        let locs = state.redis.mget_worker_locations(chunk).await?;
        location_by_id.extend(locs);
    }
    let busy_db = busy_operator_ids(state, &uuids).await?;

    let stretch = radius_stretch.max(1.0);
    let mut in_radius = Vec::new();
    for row in &rows {
        let worker_uuid = row.get::<Uuid, _>("userId");
        let worker_id = worker_uuid.to_string();
        if busy_db.contains(&worker_uuid) {
            continue;
        }
        let status = status_by_id
            .get(&worker_id)
            .map(String::as_str)
            .unwrap_or("available");
        if status == "busy" {
            continue;
        }
        let coords = if let Some(loc) = location_by_id.get(&worker_id).copied() {
            loc
        } else {
            let lat_dec = row
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLat")
                .ok()
                .flatten();
            let lng_dec = row
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLng")
                .ok()
                .flatten();
            match (lat_dec, lng_dec) {
                (Some(la), Some(lo)) => (decimal_f64(la), decimal_f64(lo)),
                _ => continue,
            }
        };
        let distance = haversine_km(lat, lng, coords.0, coords.1);
        if distance > MAX_DISPATCH_RADIUS_KM {
            continue;
        }
        let limit = row
            .try_get::<i32, _>("serviceRadiusKm")
            .ok()
            .map(|r| r as f64)
            .unwrap_or(DEFAULT_SERVICE_RADIUS_KM)
            * stretch;
        let limit = limit.min(MAX_DISPATCH_RADIUS_KM);
        if distance > limit {
            continue;
        }
        let rating = row
            .try_get::<rust_decimal::Decimal, _>("rating")
            .ok()
            .map(decimal_f64)
            .unwrap_or(0.0);
        let languages = parse_skills(row.try_get::<Option<String>, _>("languages").ok().flatten());
        in_radius.push(DispatchWorker {
            id: worker_id,
            distance_km: (distance * 10.0).round() / 10.0,
            rating,
            languages,
        });
    }

    in_radius.sort_by(|a, b| {
        a.distance_km
            .partial_cmp(&b.distance_km)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    in_radius.truncate(MAX_NEARBY_CANDIDATES);

    in_radius.sort_by(|a, b| {
        let dist = a
            .distance_km
            .partial_cmp(&b.distance_km)
            .unwrap_or(std::cmp::Ordering::Equal);
        if dist != std::cmp::Ordering::Equal {
            return dist;
        }
        b.rating.partial_cmp(&a.rating).unwrap_or(std::cmp::Ordering::Equal)
    });

    Ok(in_radius)
}

pub fn select_broadcast_targets(
    nearby: Vec<DispatchWorker>,
    preferred_languages: &[String],
) -> Vec<String> {
    let wanted: Vec<String> = preferred_languages
        .iter()
        .map(|l| l.to_lowercase())
        .collect();
    let mut eligible: Vec<DispatchWorker> = if wanted.is_empty() {
        nearby
    } else {
        nearby
            .into_iter()
            .filter(|w| {
                if w.languages.is_empty() {
                    return true;
                }
                w.languages
                    .iter()
                    .any(|lang| wanted.contains(&lang.to_lowercase()))
            })
            .collect()
    };

    eligible.sort_by(|a, b| {
        let dist = a
            .distance_km
            .partial_cmp(&b.distance_km)
            .unwrap_or(std::cmp::Ordering::Equal);
        if dist != std::cmp::Ordering::Equal {
            return dist;
        }
        b.rating
            .partial_cmp(&a.rating)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    eligible
        .into_iter()
        .take(MAX_BROADCAST_FANOUT)
        .map(|w| w.id)
        .collect()
}

pub async fn find_broadcast_target_ids(
    state: &AppState,
    requester_id: &str,
    skill: &str,
    lat: f64,
    lng: f64,
    preferred_languages: &[String],
    radius_stretch: f64,
) -> AppResult<Vec<String>> {
    let nearby =
        find_nearby_for_dispatch(state, requester_id, skill, lat, lng, radius_stretch).await?;
    Ok(select_broadcast_targets(nearby, preferred_languages))
}

async fn find_nearby_for_dispatch(
    state: &AppState,
    requester_id: &str,
    skill: &str,
    lat: f64,
    lng: f64,
    radius_stretch: f64,
) -> AppResult<Vec<DispatchWorker>> {
    let result = tokio::time::timeout(
        std::time::Duration::from_secs(3),
        load_nearby_for_dispatch(state, requester_id, skill, lat, lng, radius_stretch),
    )
    .await;
    match result {
        Ok(Err(AppError::Anyhow(error))) => {
            tracing::warn!(%error, "Worker presence lookup unavailable");
        }
        Err(_) => tracing::warn!("Worker presence lookup timed out"),
        Ok(result) => return result,
    }
    Err(AppError::ServiceUnavailable("Live worker matching is temporarily unavailable. Please try again shortly.".into()))
}

async fn get_nearby(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<NearbyQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let (lat, lng) = parse_coords(&q.lat, &q.lng)?;
    let skill = q.skill.trim();
    if skill.is_empty() {
        return Err(AppError::BadRequest("skill is required".into()));
    }

    let candidates =
        find_nearby_for_dispatch(&state, &user.user_id, skill, lat, lng, 1.0).await?;
    if candidates.is_empty() {
        return Ok(Json(vec![]));
    }

    let ids: Vec<Uuid> = candidates
        .iter()
        .filter_map(|w| Uuid::parse_str(&w.id).ok())
        .collect();
    let rows = sqlx::query(
        r#"SELECT w."userId", w.skills, w."hourlyRate", w."isActive", w.rating, w."completedJobs",
                  w."reviewCount", w.bio, w.title, u.name, u."profileImageUrl"
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           WHERE w."userId" = ANY($1)"#,
    )
    .bind(&ids)
    .fetch_all(&state.db)
    .await?;

    let distance_by_id: std::collections::HashMap<String, f64> = candidates
        .iter()
        .map(|w| (w.id.clone(), w.distance_km))
        .collect();

    let nearby_ids: Vec<String> = rows
        .iter()
        .map(|r| r.get::<Uuid, _>("userId").to_string())
        .collect();
    let status_by_id = state.redis.mget_worker_statuses(&nearby_ids).await?;
    let mut result = Vec::new();
    for row in &rows {
        let worker_id = row.get::<Uuid, _>("userId").to_string();
        let distance = distance_by_id.get(&worker_id).copied().unwrap_or(0.0);
        let status = status_by_id
            .get(&worker_id)
            .cloned()
            .unwrap_or_else(|| "available".into());
        result.push(worker_nearby_json(row, distance, &status));
    }

    result.sort_by(|a, b| {
        let da = a.get("distance_km").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let db = b.get("distance_km").and_then(|v| v.as_f64()).unwrap_or(0.0);
        if da != db {
            return da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal);
        }
        let ra = a.get("rating").and_then(|v| v.as_f64()).unwrap_or(0.0);
        let rb = b.get("rating").and_then(|v| v.as_f64()).unwrap_or(0.0);
        rb.partial_cmp(&ra).unwrap_or(std::cmp::Ordering::Equal)
    });

    Ok(Json(result))
}

#[derive(Deserialize)]
struct CountsQuery {
    lat: String,
    lng: String,
}

async fn get_nearby_counts(
    State(state): State<AppState>,
    Query(q): Query<CountsQuery>,
) -> AppResult<Json<Value>> {
    let (lat, lng) = parse_coords(&q.lat, &q.lng)?;
    let cache_key = format!("nearby:counts:{:.2}:{:.2}", lat, lng);
    if let Some(cached) = state.redis.get(&cache_key).await? {
        if let Ok(v) = serde_json::from_str::<Value>(&cached) {
            return Ok(Json(v));
        }
    }

    let trade_rows = sqlx::query(
        r#"SELECT label FROM master_entries
           WHERE type::text = 'PRO_TRADE' AND "isActive" = true
           ORDER BY "createdAt" DESC LIMIT 2000"#,
    )
    .fetch_all(&state.db)
    .await?;

    let labels: Vec<String> = trade_rows
        .iter()
        .filter_map(|r| r.try_get::<String, _>("label").ok())
        .filter(|l| !l.is_empty())
        .collect();
    if labels.is_empty() {
        return Ok(Json(json!({})));
    }

    let nearby_ids = state
        .redis
        .search_nearby_worker_ids(lat, lng, MAX_DISPATCH_RADIUS_KM)
        .await?;
    let near_set = nearby_ids.map(|ids| ids.into_iter().collect::<HashSet<_>>());

    let mut counts = serde_json::Map::new();
    for label in &labels {
        let ids = state.redis.get_worker_ids_by_skill(label).await.unwrap_or_default();
        let count = match &near_set {
            None => ids.len(),
            Some(set) => ids.iter().filter(|id| set.contains(*id)).count(),
        };
        counts.insert(label.clone(), json!(count));
    }

    let payload = Value::Object(counts);
    let _ = state
        .redis
        .set(&cache_key, &payload.to_string(), 45)
        .await;
    Ok(Json(payload))
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
        r#"SELECT b.id, b.skill, b.amount, b."totalAmount", b."updatedAt", u.name AS "customerName"
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

    let strike_count = profile.try_get::<i32, _>("strikeCount").unwrap_or(0);
    let suspended = strike_count >= SUSPENSION_STRIKE_THRESHOLD;
    let can_accept_instant =
        profile_show_availability_control(&profile, credits, is_active);

    Ok(Json(json!({
        "skills": skills,
        "activeSkills": active_skills,
        "isActive": is_active,
        "verificationStatus": verification,
        "rating": rating,
        "serviceRadiusKm": service_radius,
        "languages": parse_skills(profile.try_get::<Option<String>, _>("languages").ok().flatten()),
        "jobCredits": credits,
        "strikeCount": strike_count,
        "suspended": suspended,
        "canAcceptInstantJobs": can_accept_instant,
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
        let credits = job_credits(&state, uid).await?;
        if !profile_can_go_online(&profile, credits) {
            let strike_count = profile.try_get::<i32, _>("strikeCount").unwrap_or(0);
            if strike_count >= SUSPENSION_STRIKE_THRESHOLD {
                return Err(AppError::BadRequest(
                    "Your account is suspended after repeated job violations. Open Profile → Strikes to see the reasons and file an appeal — our team reviews every appeal.".into(),
                ));
            }
            if !profile_is_registered_pro(&profile) {
                return Err(AppError::BadRequest(
                    "Complete your pro registration before going online for instant jobs.".into(),
                ));
            }
            let verification = profile.get::<String, _>("verificationStatus");
            if verification != "VERIFIED" {
                return Err(AppError::BadRequest(
                    "Your profile is not verified yet. Please complete the verification process to go live.".into(),
                ));
            }
            let languages =
                parse_skills(profile.try_get::<Option<String>, _>("languages").ok().flatten());
            if languages.is_empty() {
                return Err(AppError::BadRequest(
                    "Select at least one language you speak before going live.".into(),
                ));
            }
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

    let all_skills = parse_skills(profile.try_get::<Option<String>, _>("skills").ok().flatten());
    let active_skills =
        parse_skills(profile.try_get::<Option<String>, _>("activeSkills").ok().flatten());
    let dispatch_skills = dispatchable_skills(&all_skills, &active_skills);

    if target {
        let _ = state
            .redis
            .set_worker_status(&user.user_id, "available")
            .await;
        let lat = body.lat.or_else(|| {
            profile
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLat")
                .ok()
                .flatten()
                .map(decimal_f64)
        });
        let lng = body.lng.or_else(|| {
            profile
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLng")
                .ok()
                .flatten()
                .map(decimal_f64)
        });
        if let (Some(lat), Some(lng)) = (lat, lng) {
            let _ = state.redis.update_worker_location(&user.user_id, lat, lng).await;
        }
        let _ = state
            .redis
            .index_worker_skills(&user.user_id, &dispatch_skills)
            .await;
    } else {
        let _ = state
            .redis
            .clear_worker_live_state(&user.user_id, &all_skills)
            .await;
    }

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
                .filter_map(|s| s.as_str().map(|v| v.trim().to_string()))
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();
    let profile = ensure_profile(&state, uid).await?;
    let is_active = profile.get::<bool, _>("isActive");
    if langs.is_empty() && is_active {
        return Err(AppError::BadRequest(
            "Select at least one language you speak, or go offline first.".into(),
        ));
    }
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
    let _ = state
        .redis
        .update_worker_location(&user.user_id, body.lat, body.lng)
        .await;
    Ok(Json(json!({ "message": "Location updated" })))
}

#[derive(Deserialize)]
struct VerificationQueueQuery {
    status: Option<String>,
}

async fn verification_queue(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<VerificationQueueQuery>,
) -> AppResult<Json<Vec<Value>>> {
    require_admin_page(&user, "verifications")?;
    let status = q
        .status
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let cols = worker_profile_cols("w");
    let rows = sqlx::query(&format!(
        r#"SELECT {cols}, u.name, u."phoneNumber", tp."photoUrl", tp.certificates
           FROM worker_profiles w
           JOIN users u ON u.id = w."userId"
           LEFT JOIN talent_profiles tp ON tp."userId" = w."userId"
           WHERE ($1::text IS NULL OR w."verificationStatus"::text = $1)
           ORDER BY w.id DESC"#
    ))
    .bind(status)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(worker_json).collect()))
}

#[derive(Deserialize)]
struct VerificationBody {
    status: String,
}

async fn set_verification(
    State(state): State<AppState>,
    user: AuthUser,
    Path(user_id): Path<String>,
    Json(body): Json<VerificationBody>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "verifications")?;
    let uid = Uuid::parse_str(&user_id)?;
    let status = body.status.trim().to_uppercase();
    if status != "VERIFIED" && status != "REJECTED" {
        return Err(AppError::BadRequest(
            "status must be VERIFIED or REJECTED".into(),
        ));
    }
    let updated = sqlx::query(
        r#"UPDATE worker_profiles SET "verificationStatus" = $1::worker_profiles_verificationstatus_enum, "updatedAt" = NOW()
           WHERE "userId" = $2"#,
    )
    .bind(&status)
    .bind(uid)
    .execute(&state.db)
    .await?
    .rows_affected();
    if updated == 0 {
        return Err(AppError::NotFound("Worker profile not found".into()));
    }
    if status == "VERIFIED" {
        sqlx::query(
            r#"UPDATE users SET "isVerified" = true, "hasWorkerProfile" = true,
                   "approvalStatus" = 'APPROVED'::users_approvalstatus_enum, "updatedAt" = NOW()
               WHERE id = $1"#,
        )
        .bind(uid)
        .execute(&state.db)
        .await?;
    }
    Ok(Json(json!({
        "userId": uid.to_string(),
        "verificationStatus": status,
    })))
}

async fn get_by_id(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&id)?;
    let cols = worker_profile_cols("w");
    let row = sqlx::query(&format!(
        r#"SELECT {cols}, u.name, u."profileImageUrl"
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
        "name": row.try_get::<Option<String>, _>("name").ok().flatten(),
        "phone": row.try_get::<Option<String>, _>("phoneNumber").ok().flatten().unwrap_or_default(),
        "skills": parse_skills(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "hourlyRate": row.try_get::<rust_decimal::Decimal, _>("hourlyRate").ok().and_then(|d| d.to_f64()).unwrap_or(0.0),
        "bio": row.try_get::<Option<String>, _>("bio").ok().flatten().unwrap_or_default(),
        "isActive": row.try_get::<bool, _>("isActive").ok(),
        "verificationStatus": row.try_get::<String, _>("verificationStatus").ok().unwrap_or_else(|| "PENDING".into()),
        "languages": parse_skills(row.try_get::<Option<String>, _>("languages").ok().flatten()),
        "photoUrl": row.try_get::<Option<String>, _>("photoUrl").ok().flatten(),
        "certificates": parse_skills(row.try_get::<Option<String>, _>("certificates").ok().flatten()),
        "lastLat": row.try_get::<Option<rust_decimal::Decimal>, _>("lastLat").ok().flatten(),
        "lastLng": row.try_get::<Option<rust_decimal::Decimal>, _>("lastLng").ok().flatten(),
    })
}

fn worker_list_json(row: &sqlx::postgres::PgRow) -> Value {
    let user_id = row
        .try_get::<Uuid, _>("userId")
        .ok()
        .map(|u| u.to_string())
        .or_else(|| row.try_get::<Uuid, _>("id").ok().map(|u| u.to_string()))
        .unwrap_or_default();
    let rating = row
        .try_get::<rust_decimal::Decimal, _>("rating")
        .ok()
        .map(decimal_f64)
        .unwrap_or(0.0);
    let hourly_rate = row
        .try_get::<rust_decimal::Decimal, _>("hourlyRate")
        .ok()
        .map(decimal_f64)
        .unwrap_or(0.0);
    json!({
        "id": user_id,
        "name": row.try_get::<Option<String>, _>("name").ok().flatten().unwrap_or_default(),
        "title": row.try_get::<Option<String>, _>("title").ok().flatten().unwrap_or_default(),
        "bio": row.try_get::<Option<String>, _>("bio").ok().flatten().unwrap_or_default(),
        "image_url": row.try_get::<Option<String>, _>("profileImageUrl").ok().flatten().unwrap_or_else(|| "https://i.pravatar.cc/150".into()),
        "rating": rating,
        "completed_jobs": row.try_get::<i32, _>("completedJobs").ok().unwrap_or(0),
        "review_count": row.try_get::<i32, _>("reviewCount").ok().unwrap_or(0),
        "is_featured": false,
        "hourly_rate": hourly_rate,
        "skills": parse_skills(row.try_get::<Option<String>, _>("skills").ok().flatten()),
        "availability_tags": [],
        "primary_type": "manual",
        "status": if row.try_get::<bool, _>("isActive").ok().unwrap_or(false) { "available" } else { "offline" },
    })
}

fn worker_nearby_json(row: &sqlx::postgres::PgRow, distance_km: f64, status: &str) -> Value {
    let mut dto = worker_list_json(row);
    if let Some(obj) = dto.as_object_mut() {
        obj.insert(
            "distance_km".into(),
            json!((distance_km * 10.0).round() / 10.0),
        );
        obj.insert("status".into(), json!(status));
    }
    dto
}

pub async fn force_offline(state: &AppState, user_id: &str) -> AppResult<()> {
    let uid = Uuid::parse_str(user_id)?;
    let profile = load_profile(state, uid).await?;
    if profile.is_none() {
        return Ok(());
    }
    let profile = profile.unwrap();
    if !profile.get::<bool, _>("isActive") {
        return Ok(());
    }

    let all_skills = parse_skills(profile.try_get::<Option<String>, _>("skills").ok().flatten());

    sqlx::query(r#"UPDATE worker_profiles SET "isActive" = false WHERE "userId" = $1"#)
        .bind(uid)
        .execute(&state.db)
        .await?;

    let _ = tokio::time::timeout(
        crate::redis::OPTIONAL_REDIS_TIMEOUT,
        state.redis.clear_worker_live_state(user_id, &all_skills),
    )
    .await;
    Ok(())
}

pub async fn set_worker_status(state: &AppState, user_id: &str, status: &str) {
    let _ = tokio::time::timeout(
        crate::redis::OPTIONAL_REDIS_TIMEOUT,
        state.redis.set_worker_status(user_id, status),
    )
    .await;
}

/// Derive Redis availability from current bookings + live eligibility.
/// Delayed/repeated outbox events cannot free a busy worker or resurrect an offline one.
pub async fn sync_worker_availability(state: &AppState, user_id: &str) {
    let Ok(uid) = Uuid::parse_str(user_id) else {
        return;
    };
    let busy = sqlx::query_scalar::<_, bool>(
        r#"SELECT EXISTS(
               SELECT 1 FROM bookings
               WHERE "operatorId" = $1
                 AND status::text IN ('ACCEPTED','ARRIVED','ACTIVE')
           )"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false);
    if busy {
        set_worker_status(state, user_id, "busy").await;
        return;
    }

    let is_live = sqlx::query_scalar::<_, bool>(
        r#"SELECT COALESCE(w."isActive", false)
           FROM worker_profiles w
           WHERE w."userId" = $1"#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten()
    .unwrap_or(false);
    if !is_live {
        return;
    }

    let has_presence = tokio::time::timeout(
        crate::redis::OPTIONAL_REDIS_TIMEOUT,
        state.redis.get_worker_location(user_id),
    )
    .await
    .ok()
    .and_then(Result::ok)
    .flatten()
    .is_some();
    if has_presence {
        set_worker_status(state, user_id, "available").await;
    }
}

/// Operators currently on an Instant Help job — used when Redis status is missing/stale.
pub async fn busy_operator_ids(state: &AppState, candidates: &[Uuid]) -> AppResult<HashSet<Uuid>> {
    if candidates.is_empty() {
        return Ok(HashSet::new());
    }
    let rows: Vec<Uuid> = sqlx::query_scalar(
        r#"SELECT DISTINCT "operatorId" FROM bookings
           WHERE "operatorId" = ANY($1)
             AND status::text IN ('ACCEPTED','ARRIVED','ACTIVE')"#,
    )
    .bind(candidates)
    .fetch_all(&state.db)
    .await?;
    Ok(rows.into_iter().collect())
}

async fn config_number(state: &AppState, key: &str, fallback: i32) -> i32 {
    let raw: Option<String> = sqlx::query_scalar(
        r#"SELECT value FROM master_entries
           WHERE type::text = 'CONFIGURATION' AND label = $1 AND "isActive" = true LIMIT 1"#,
    )
    .bind(key)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    match raw {
        Some(s) => s
            .trim()
            .parse::<i32>()
            .ok()
            .filter(|n| *n >= 0)
            .unwrap_or(fallback),
        None => fallback,
    }
}

pub async fn refresh_worker_snapshot(state: &AppState, user_id: &str) -> AppResult<()> {
    let _ = state
        .redis
        .del(&format!("worker:snapshot:{user_id}"))
        .await;
    Ok(())
}

pub async fn periodic_jobs_per_payment(state: &AppState) -> i32 {
    config_number(state, "go_live_jobs_per_payment", 0).await
}

pub async fn record_strike(
    state: &AppState,
    user_id: &str,
    strike_type: &str,
    booking_id: &str,
    reason: &str,
) -> AppResult<()> {
    let uid = Uuid::parse_str(user_id)?;
    let bid = Uuid::parse_str(booking_id)?;

    let mut tx=state.db.begin().await?;
    let profile = sqlx::query(&format!(r#"SELECT {WORKER_PROFILE_COLS} FROM worker_profiles WHERE "userId"=$1 FOR UPDATE"#))
        .bind(uid).fetch_optional(&mut *tx).await?;
    if profile.is_none() {
        return Ok(());
    }
    let profile = profile.unwrap();
    let skills = parse_skills(profile.try_get::<Option<String>, _>("skills").ok().flatten());
    let duplicate:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM worker_strikes WHERE "workerUserId"=$1 AND "bookingId"=$2 AND type::text=$3)"#)
        .bind(user_id).bind(bid).bind(strike_type).fetch_one(&mut *tx).await?;
    if duplicate {
        let suspended=profile.get::<i32,_>("strikeCount")>=SUSPENSION_STRIKE_THRESHOLD;
        tx.commit().await?;
        if suspended {state.redis.clear_worker_live_state(user_id,&skills).await.map_err(|e|AppError::Internal(e.to_string()))?;}
        return Ok(());
    }

    sqlx::query(
        r#"INSERT INTO worker_strikes (id, "workerUserId", "bookingId", type, reason, status)
           VALUES ($1, $2, $3, $4::worker_strikes_type_enum, $5, 'ACTIVE')"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(bid)
    .bind(strike_type)
    .bind(reason)
    .execute(&mut *tx)
    .await?;

    let strike_count: i32 = sqlx::query_scalar(
        r#"UPDATE worker_profiles SET "strikeCount" = COALESCE("strikeCount", 0) + 1
           WHERE "userId" = $1 RETURNING "strikeCount""#,
    )
    .bind(uid)
    .fetch_one(&mut *tx)
    .await?;

    let suspended = strike_count >= SUSPENSION_STRIKE_THRESHOLD;
    if suspended {
        sqlx::query(r#"UPDATE worker_profiles SET "isActive" = false WHERE "userId" = $1"#)
            .bind(uid)
            .execute(&mut *tx)
            .await?;
    }

    let (title, body) = if suspended {
        (
            "Account suspended — you can appeal".to_string(),
            format!(
                "{} You now have {} strikes and cannot go live. Open Profile → Strikes to appeal — our team reviews every appeal.",
                reason,
                strike_count
            ),
        )
    } else {
        (
            format!("Strike {} of {}", strike_count, SUSPENSION_STRIKE_THRESHOLD),
            format!(
                "{} At {} strikes you will be suspended. You can view or appeal this in Profile → Strikes.",
                reason,
                SUSPENSION_STRIKE_THRESHOLD
            ),
        )
    };
    crate::outbox::notify(&mut tx,bid,uid,&title,&body,json!({"type":"worker_strike",
        "strikeCount":strike_count.to_string(),"suspended":suspended.to_string()})).await?;
    tx.commit().await?;
    if suspended {state.redis.clear_worker_live_state(user_id,&skills).await.map_err(|e|AppError::Internal(e.to_string()))?;}

    Ok(())
}

pub async fn mark_period_fee_paid(
    state: &AppState,
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    payment_order_id: Uuid,
    uid: Uuid,
) -> AppResult<()> {
    sqlx::query(r#"UPDATE worker_profiles SET "jobsSincePayment" = 0 WHERE "userId" = $1"#)
        .bind(uid)
        .execute(&mut **tx)
        .await?;
    let jobs_included = periodic_jobs_per_payment(state).await;
    crate::outbox::notify(
        tx,
        payment_order_id,
        uid,
        "Payment received",
        &format!("Your next {} jobs are unlocked — go live when ready!", jobs_included),
        json!({"type": "period_fee_paid"}),
    )
    .await?;
    Ok(())
}
