use std::collections::HashMap;
use std::time::Instant;

use rust_decimal::prelude::ToPrimitive;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;

use super::events;
use super::features::{self, PairInput};
use super::hard_filter::{self, GateInput};
use super::reciprocal;
use super::semantic;
use super::skills::{self, SkillNeed};
use super::structured;
use super::weights::MatchingWeights;

struct Seeker {
    profile_id: Option<Uuid>,
    skills: Vec<String>,
    roles: Vec<String>,
    employment: Option<String>,
    expected_salary: f32,
    years: f32,
    lat: Option<f64>,
    lng: Option<f64>,
    radius: f64,
    availability: String,
    active: bool,
    work_mode: Option<String>,
}

struct JobView {
    id: Uuid,
    employer_id: Uuid,
    business_id: Option<Uuid>,
    title: String,
    description: String,
    skills: Vec<String>,
    category: String,
    employment: String,
    experience_label: String,
    experience_min: f32,
    location: String,
    salary_min: f32,
    salary_max: f32,
    salary_period: String,
    work_mode: String,
    lat: Option<f64>,
    lng: Option<f64>,
    business_name: Option<String>,
    business_ok: bool,
    published: bool,
    openings: i32,
}

pub async fn jobs_for_seeker(
    state: &AppState,
    user_id: Uuid,
    page: i64,
    limit: i64,
) -> AppResult<Value> {
    let started = Instant::now();
    let seeker = load_seeker(state, user_id).await?;
    if seeker.profile_id.is_some() && !seeker.active {
        return Ok(json!({"items": [], "page": page, "limit": limit, "total": 0}));
    }
    let weights = load_weights(state).await;
    let related = load_related(state).await;
    let radius_m = seeker.radius * 1000.0;
    let rows = sqlx::query(
        r#"SELECT j.id, j.title, j.description, j."requiredSkills", j."jobType", j.experience,
                  j.location, j."salaryMin", j."salaryMax", j."isActive", j."employerId", j."businessId",
                  j."workMode", j."salaryPeriod", j."experienceMin", j.lat, j.lng, j.openings, j.status,
                  b.name AS "businessName",
                  (j."businessId" IS NOT NULL AND b.status::text = 'VERIFIED') AS business_ok
           FROM job_posts j
           LEFT JOIN businesses b ON b.id = j."businessId"
           WHERE j."employerId" <> $1 AND j."isActive" = true
             AND COALESCE(j.status, 'PUBLISHED') = 'PUBLISHED'
             AND (
               j."workMode" = 'REMOTE'
               OR $2::float8 IS NULL
               OR j.geo IS NULL
               OR ST_DWithin(j.geo, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, $4)
             )
           ORDER BY j."createdAt" DESC
           LIMIT 300"#,
    )
    .bind(user_id)
    .bind(seeker.lat)
    .bind(seeker.lng)
    .bind(radius_m)
    .fetch_all(&state.db)
    .await?;
    let before = rows.len();
    let job_ids: Vec<Uuid> = rows.iter().map(|row| row.get("id")).collect();
    let sims = job_similarities(state, &job_ids, &seeker).await;
    let mut ranked = Vec::new();
    let mut after_hard = 0;
    for row in &rows {
        let job = job_from_row(row);
        if hard_filter::admit(&gate(&seeker, &job, true)).is_err() {
            continue;
        }
        after_hard += 1;
        if let Some(card) = score_pair(&seeker, &job, &related, &weights, sims.get(&job.id).copied()) {
            ranked.push((job, card));
        }
    }
    ranked.sort_by(|a, b| {
        b.1.score
            .partial_cmp(&a.1.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    let total = ranked.len();
    let start = ((page - 1).max(0) * limit) as usize;
    let page_rows: Vec<_> = ranked.into_iter().skip(start).take(limit as usize).collect();
    for (job, card) in &page_rows {
        events::record(
            state,
            Some(user_id),
            Some(job.id),
            seeker.profile_id,
            job.business_id,
            "JOB_IMPRESSION",
            Some(card.score),
        )
        .await?;
    }
    tracing::info!(
        before,
        after_hard,
        after_rank = total,
        db_ms = started.elapsed().as_millis() as u64,
        "job recommendation"
    );
    Ok(json!({
        "items": page_rows.iter().map(|(job, card)| job_card(job, card)).collect::<Vec<_>>(),
        "page": page,
        "limit": limit,
        "total": total,
    }))
}

pub async fn candidates_for_job(state: &AppState, employer_id: Uuid, job_id: Uuid) -> AppResult<Value> {
    let started = Instant::now();
    let job_row = sqlx::query(
        r#"SELECT j.id, j.title, j.description, j."requiredSkills", j."jobType", j.experience,
                  j.location, j."salaryMin", j."salaryMax", j."isActive", j."employerId", j."businessId",
                  j."workMode", j."salaryPeriod", j."experienceMin", j.lat, j.lng, j.openings, j.status,
                  b.name AS "businessName",
                  (j."businessId" IS NOT NULL AND b.status::text = 'VERIFIED') AS business_ok
           FROM job_posts j
           LEFT JOIN businesses b ON b.id = j."businessId"
           WHERE j.id = $1 AND j."employerId" = $2"#,
    )
    .bind(job_id)
    .bind(employer_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Job post not found on your account".into()))?;
    let job = job_from_row(&job_row);
    let weights = load_weights(state).await;
    let related = load_related(state).await;
    let people = sqlx::query(
        r#"SELECT t.id, t."userId", u.name, t.skills, t."preferredRoles", t."expectedSalary",
                  t.experience, t.lat, t.lng, t."travelRadiusKm", t.availability, t."profileStatus",
                  t."preferredWorkMode"
           FROM talent_profiles t
           JOIN users u ON u.id = t."userId"
           WHERE t."userId" <> $1
             AND COALESCE(t."profileStatus", 'ACTIVE') = 'ACTIVE'
             AND (
               $2 = 'REMOTE'
               OR $3::float8 IS NULL
               OR t.geo IS NULL
               OR ST_DWithin(
                    t.geo,
                    ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography,
                    GREATEST(COALESCE(t."travelRadiusKm", 25), 1) * 1000
                  )
             )
           ORDER BY t."updatedAt" DESC NULLS LAST
           LIMIT 200"#,
    )
    .bind(employer_id)
    .bind(job.work_mode.to_ascii_uppercase())
    .bind(job.lat)
    .bind(job.lng)
    .fetch_all(&state.db)
    .await?;
    let before = people.len();
    let profile_ids: Vec<Uuid> = people.iter().map(|row| row.get("id")).collect();
    let sims = candidate_similarities(state, &profile_ids, &job).await;
    let mut ranked = Vec::new();
    for row in &people {
        let seeker = seeker_from_candidate_row(row);
        if hard_filter::admit(&gate(&seeker, &job, false)).is_err() {
            continue;
        }
        let profile_id: Uuid = row.get("id");
        if let Some(card) = score_pair(&seeker, &job, &related, &weights, sims.get(&profile_id).copied()) {
            ranked.push((row, card));
        }
    }
    ranked.sort_by(|a, b| b.1.score.partial_cmp(&a.1.score).unwrap_or(std::cmp::Ordering::Equal));
    ranked.truncate(30);
    tracing::info!(
        before,
        after_rank = ranked.len(),
        rank_ms = started.elapsed().as_millis() as u64,
        "candidate recommendation"
    );
    Ok(json!({
        "items": ranked.iter().map(|(row, card)| candidate_card(row, card)).collect::<Vec<_>>(),
    }))
}

pub async fn annotate_job(state: &AppState, user_id: Uuid, job_id: Uuid) -> AppResult<Option<Value>> {
    let seeker = load_seeker(state, user_id).await?;
    let row = sqlx::query(
        r#"SELECT j.id, j.title, j.description, j."requiredSkills", j."jobType", j.experience,
                  j.location, j."salaryMin", j."salaryMax", j."isActive", j."employerId", j."businessId",
                  j."workMode", j."salaryPeriod", j."experienceMin", j.lat, j.lng, j.openings, j.status,
                  b.name AS "businessName",
                  (j."businessId" IS NOT NULL AND b.status::text = 'VERIFIED') AS business_ok
           FROM job_posts j LEFT JOIN businesses b ON b.id = j."businessId"
           WHERE j.id = $1"#,
    )
    .bind(job_id)
    .fetch_optional(&state.db)
    .await?;
    let Some(row) = row else { return Ok(None) };
    let job = job_from_row(&row);
    if job.employer_id == user_id {
        return Ok(None);
    }
    events::record(state, Some(user_id), Some(job_id), seeker.profile_id, job.business_id, "JOB_VIEW", None).await?;
    let related = load_related(state).await;
    let weights = load_weights(state).await;
    if hard_filter::admit(&gate(&seeker, &job, true)).is_err() {
        return Ok(Some(json!({"matchScore": null, "reasons": [], "warnings": []})));
    }
    let sims = job_similarities(state, &[job.id], &seeker).await;
    Ok(score_pair(&seeker, &job, &related, &weights, sims.get(&job.id).copied()).map(|card| {
        json!({
            "matchScore": card.score.round() as i32,
            "reasons": card.reasons,
            "warnings": card.warnings,
            "distanceKm": card.distance_km,
            "distanceExact": card.distance_exact,
        })
    }))
}

struct Card {
    score: f32,
    reasons: Vec<String>,
    warnings: Vec<String>,
    distance_km: Option<f64>,
    distance_exact: bool,
}

fn score_pair(
    seeker: &Seeker,
    job: &JobView,
    related: &[(String, String)],
    weights: &MatchingWeights,
    similarity: Option<f32>,
) -> Option<Card> {
    let (distance_km, exact) = match (seeker.lat, seeker.lng, job.lat, job.lng) {
        (Some(a), Some(b), Some(c), Some(d)) => (Some(super::geo::haversine_km(a, b, c, d)), true),
        _ => (None, false),
    };
    let input = PairInput {
        job_category: format!("{} {}", job.title, job.category),
        seeker_roles: seeker.roles.clone(),
        job_skills: job.skills.iter().cloned().map(|key| SkillNeed { key, required: true }).collect(),
        seeker_skills: seeker.skills.iter().map(|s| skills::normalize_skill(s)).collect(),
        related: related.to_vec(),
        distance_km,
        distance_exact: exact,
        travel_radius_km: seeker.radius,
        remote: job.work_mode.eq_ignore_ascii_case("REMOTE"),
        job_employment: job.employment.clone(),
        seeker_employment: seeker.employment.clone(),
        job_salary_min: job.salary_min,
        job_salary_max: job.salary_max,
        job_salary_period: job.salary_period.clone(),
        expected_salary: seeker.expected_salary,
        expected_period: "MONTHLY".into(),
        candidate_years: seeker.years,
        preferred_years: job.experience_min,
        availability: seeker.availability.clone(),
    };
    let mut features = features::build(&input)?;
    let candidate_fit = structured::score(&features, weights);
    let employer_fit = reciprocal::employer_fit(&features);
    let mutual = reciprocal::mutual(candidate_fit, employer_fit);
    let blended = semantic::hybrid(mutual.mutual_fit, similarity, weights);
    features.candidate_fit = candidate_fit;
    features.employer_fit = employer_fit;
    let explained = super::explanation::build(&features);
    Some(Card {
        score: blended,
        reasons: explained.reasons,
        warnings: explained.warnings,
        distance_km,
        distance_exact: exact,
    })
}

fn gate(seeker: &Seeker, job: &JobView, seeker_side: bool) -> GateInput {
    let distance_km = match (seeker.lat, seeker.lng, job.lat, job.lng) {
        (Some(a), Some(b), Some(c), Some(d)) => Some(super::geo::haversine_km(a, b, c, d)),
        _ => None,
    };
    GateInput {
        job_published: job.published,
        business_verified: job.business_ok,
        profile_active: if seeker_side { true } else { seeker.active },
        work_mode: job.work_mode.clone(),
        seeker_work_mode: seeker.work_mode.clone(),
        job_employment: job.employment.clone(),
        seeker_employment: seeker.employment.clone(),
        distance_km,
        travel_radius_km: seeker.radius,
    }
}

fn job_card(job: &JobView, card: &Card) -> Value {
    json!({
        "id": job.id.to_string(),
        "employerId": job.employer_id.to_string(),
        "businessId": job.business_id.map(|id| id.to_string()),
        "businessName": job.business_name,
        "businessVerified": job.business_ok,
        "title": job.title,
        "description": job.description,
        "requiredSkills": job.skills,
        "jobType": job.employment,
        "experience": job.experience_label,
        "location": job.location,
        "salaryMin": job.salary_min,
        "salaryMax": job.salary_max,
        "salaryPeriod": job.salary_period,
        "workMode": job.work_mode,
        "openings": job.openings,
        "isActive": job.published,
        "matchScore": card.score.round() as i32,
        "reasons": card.reasons,
        "warnings": card.warnings,
        "distanceKm": card.distance_km.filter(|_| card.distance_exact),
        "distanceExact": card.distance_exact,
    })
}

/// Public hiring card. Phone, email, and documents are never copied in.
pub fn candidate_card(row: &sqlx::postgres::PgRow, card: &Card) -> Value {
    let name = public_name(&text_col(row, "name"));
    json!({
        "candidateId": row.get::<Uuid, _>("userId").to_string(),
        "profileId": row.get::<Uuid, _>("id").to_string(),
        "name": name,
        "skills": crate::common::pg::string_list(row, "skills"),
        "roles": crate::common::pg::string_list(row, "preferredRoles"),
        "experienceYears": skills::parse_years(row.try_get::<Option<String>, _>("experience").ok().flatten().as_deref().unwrap_or("")),
        "expectedSalary": num(row, "expectedSalary"),
        "availability": row.try_get::<String, _>("availability").unwrap_or_else(|_| "IMMEDIATE".into()),
        "distanceKm": card.distance_km.filter(|_| card.distance_exact),
        "matchScore": card.score.round() as i32,
        "reasons": card.reasons,
        "warnings": card.warnings,
    })
}

pub fn public_name(full: &str) -> String {
    let parts: Vec<&str> = full.split_whitespace().filter(|p| !p.is_empty()).collect();
    match parts.as_slice() {
        [] => "Candidate".into(),
        [only] => (*only).to_string(),
        [first, .., last] => {
            let initial = last.chars().next().unwrap_or(' ');
            format!("{first} {initial}.")
        }
    }
}

async fn load_seeker(state: &AppState, user_id: Uuid) -> AppResult<Seeker> {
    let row = sqlx::query(
        r#"SELECT id, skills, "preferredRoles", "expectedSalary", experience, lat, lng,
                  "travelRadiusKm", availability, "profileStatus", "preferredWorkMode"
           FROM talent_profiles WHERE "userId" = $1"#,
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    let pref = sqlx::query(
        r#"SELECT "jobType", skills, "employmentType"::text AS "employmentType", "experienceYears", "expectedSalary"
           FROM job_preferences WHERE "userId" = $1 AND "isActive" = true
           ORDER BY "createdAt" DESC LIMIT 1"#,
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    let mut seeker = if let Some(row) = row {
        Seeker {
            profile_id: Some(row.get("id")),
            skills: crate::common::pg::string_list(&row, "skills"),
            roles: crate::common::pg::string_list(&row, "preferredRoles"),
            employment: None,
            expected_salary: num(&row, "expectedSalary"),
            years: skills::parse_years(row.try_get::<Option<String>, _>("experience").ok().flatten().as_deref().unwrap_or("")),
            lat: row.try_get::<Option<f64>, _>("lat").ok().flatten(),
            lng: row.try_get::<Option<f64>, _>("lng").ok().flatten(),
            radius: row.try_get::<f64, _>("travelRadiusKm").unwrap_or(25.0).max(1.0),
            availability: row.try_get::<String, _>("availability").unwrap_or_else(|_| "IMMEDIATE".into()),
            active: row.try_get::<String, _>("profileStatus").unwrap_or_else(|_| "ACTIVE".into()) == "ACTIVE",
            work_mode: row.try_get::<Option<String>, _>("preferredWorkMode").ok().flatten(),
        }
    } else {
        Seeker {
            profile_id: None,
            skills: vec![],
            roles: vec![],
            employment: None,
            expected_salary: 0.0,
            years: 0.0,
            lat: None,
            lng: None,
            radius: 25.0,
            availability: "IMMEDIATE".into(),
            active: true,
            work_mode: None,
        }
    };
    if let Some(pref) = pref {
        if seeker.roles.is_empty() {
            if let Some(job_type) = pref.try_get::<String, _>("jobType").ok() {
                seeker.roles.push(job_type);
            }
        }
        if seeker.skills.is_empty() {
            seeker.skills = crate::common::pg::string_list(&pref, "skills");
        }
        seeker.employment = pref
            .try_get::<Option<String>, _>("employmentType")
            .ok()
            .flatten();
        if seeker.years <= 0.0 {
            seeker.years = pref.try_get::<i32, _>("experienceYears").unwrap_or(0) as f32;
        }
        if seeker.expected_salary <= 0.0 {
            seeker.expected_salary = num(&pref, "expectedSalary");
        }
    }
    Ok(seeker)
}

fn seeker_from_candidate_row(row: &sqlx::postgres::PgRow) -> Seeker {
    Seeker {
        profile_id: Some(row.get("id")),
        skills: crate::common::pg::string_list(row, "skills"),
        roles: crate::common::pg::string_list(row, "preferredRoles"),
        employment: None,
        expected_salary: num(row, "expectedSalary"),
        years: skills::parse_years(row.try_get::<Option<String>, _>("experience").ok().flatten().as_deref().unwrap_or("")),
        lat: row.try_get::<Option<f64>, _>("lat").ok().flatten(),
        lng: row.try_get::<Option<f64>, _>("lng").ok().flatten(),
        radius: row.try_get::<f64, _>("travelRadiusKm").unwrap_or(25.0).max(1.0),
        availability: row.try_get::<String, _>("availability").unwrap_or_else(|_| "IMMEDIATE".into()),
        active: true,
        work_mode: row.try_get::<Option<String>, _>("preferredWorkMode").ok().flatten(),
    }
}

fn job_from_row(row: &sqlx::postgres::PgRow) -> JobView {
    let status = row.try_get::<String, _>("status").unwrap_or_else(|_| "PUBLISHED".into());
    let active = row.try_get::<bool, _>("isActive").unwrap_or(true);
    let experience_label = row.try_get::<Option<String>, _>("experience").ok().flatten().unwrap_or_default();
    let experience_min = row
        .try_get::<Option<f64>, _>("experienceMin")
        .ok()
        .flatten()
        .unwrap_or_else(|| skills::parse_years(&experience_label) as f64) as f32;
    JobView {
        id: row.get("id"),
        employer_id: row.get("employerId"),
        business_id: row.try_get::<Option<Uuid>, _>("businessId").ok().flatten(),
        title: row.try_get::<String, _>("title").unwrap_or_default(),
        description: row.try_get::<String, _>("description").unwrap_or_default(),
        skills: crate::common::pg::string_list(row, "requiredSkills"),
        category: row.try_get::<Option<String>, _>("jobType").ok().flatten().unwrap_or_default(),
        employment: row.try_get::<Option<String>, _>("jobType").ok().flatten().unwrap_or_else(|| "Full Time".into()),
        experience_label,
        experience_min,
        location: row.try_get::<Option<String>, _>("location").ok().flatten().unwrap_or_default(),
        salary_min: money(row, "salaryMin"),
        salary_max: money(row, "salaryMax"),
        salary_period: row.try_get::<String, _>("salaryPeriod").unwrap_or_else(|_| "MONTHLY".into()),
        work_mode: row.try_get::<String, _>("workMode").unwrap_or_else(|_| "ONSITE".into()),
        lat: row.try_get::<Option<f64>, _>("lat").ok().flatten(),
        lng: row.try_get::<Option<f64>, _>("lng").ok().flatten(),
        business_name: row.try_get::<Option<String>, _>("businessName").ok().flatten(),
        business_ok: row.try_get::<bool, _>("business_ok").unwrap_or(false),
        published: active && status == "PUBLISHED",
        openings: row.try_get::<i32, _>("openings").unwrap_or(1),
    }
}

fn weight_col(row: &sqlx::postgres::PgRow, column: &str, fallback: f32) -> f32 {
    if let Ok(value) = row.try_get::<f32, _>(column) {
        return value;
    }
    if let Ok(value) = row.try_get::<f64, _>(column) {
        return value as f32;
    }
    fallback
}

fn text_col(row: &sqlx::postgres::PgRow, column: &str) -> String {
    if let Ok(value) = row.try_get::<String, _>(column) {
        return value;
    }
    row.try_get::<Option<String>, _>(column)
        .ok()
        .flatten()
        .unwrap_or_default()
}

fn money(row: &sqlx::postgres::PgRow, column: &str) -> f32 {
    if let Ok(Some(value)) = row.try_get::<Option<rust_decimal::Decimal>, _>(column) {
        return value.to_f64().unwrap_or(0.0) as f32;
    }
    num(row, column)
}

fn num(row: &sqlx::postgres::PgRow, column: &str) -> f32 {
    if let Ok(Some(value)) = row.try_get::<Option<f64>, _>(column) {
        return value as f32;
    }
    if let Ok(value) = row.try_get::<f64, _>(column) {
        return value as f32;
    }
    if let Ok(Some(value)) = row.try_get::<Option<i32>, _>(column) {
        return value as f32;
    }
    if let Ok(value) = row.try_get::<i32, _>(column) {
        return value as f32;
    }
    if let Ok(Some(value)) = row.try_get::<Option<rust_decimal::Decimal>, _>(column) {
        return value.to_f64().unwrap_or(0.0) as f32;
    }
    0.0
}

async fn job_similarities(state: &AppState, job_ids: &[Uuid], seeker: &Seeker) -> HashMap<Uuid, f32> {
    let vector = super::embeddings::embed_text(&super::embeddings::candidate_text(
        &seeker.roles,
        &seeker.skills,
        &format!("{} years", seeker.years),
    ));
    similarities(
        state,
        r#"SELECT "jobPostId" AS id, 1 - (embedding <=> $1::vector) AS sim
           FROM job_embeddings WHERE "jobPostId" = ANY($2)"#,
        job_ids,
        vector.as_deref(),
    )
    .await
}

async fn candidate_similarities(state: &AppState, profile_ids: &[Uuid], job: &JobView) -> HashMap<Uuid, f32> {
    let vector = super::embeddings::embed_text(&super::embeddings::job_text(
        &job.title,
        &job.category,
        &job.description,
        &job.skills,
    ));
    similarities(
        state,
        r#"SELECT "talentProfileId" AS id, 1 - (embedding <=> $1::vector) AS sim
           FROM candidate_embeddings WHERE "talentProfileId" = ANY($2)"#,
        profile_ids,
        vector.as_deref(),
    )
    .await
}

async fn similarities(
    state: &AppState,
    sql: &str,
    ids: &[Uuid],
    vector: Option<&[f32]>,
) -> HashMap<Uuid, f32> {
    let Some(vector) = vector else {
        return HashMap::new();
    };
    if ids.is_empty() {
        return HashMap::new();
    }
    let Ok(rows) = sqlx::query(sql)
        .bind(super::embeddings::to_literal(vector))
        .bind(ids)
        .fetch_all(&state.db)
        .await
    else {
        return HashMap::new();
    };
    rows.into_iter()
        .filter_map(|row| {
            let id = row.try_get::<Uuid, _>("id").ok()?;
            let sim = row.try_get::<f64, _>("sim").ok().map(|value| value as f32)
                .or_else(|| row.try_get::<f32, _>("sim").ok())?;
            Some((id, sim))
        })
        .collect()
}

async fn load_related(state: &AppState) -> Vec<(String, String)> {
    let Ok(rows) = sqlx::query(
        r#"SELECT a."normalizedName" AS left_name, b."normalizedName" AS right_name
           FROM skill_related r
           JOIN skills a ON a.id = r."skillId"
           JOIN skills b ON b.id = r."relatedSkillId""#,
    )
    .fetch_all(&state.db)
    .await
    else {
        return vec![];
    };
    rows.into_iter()
        .filter_map(|row| {
            Some((
                row.try_get::<String, _>("left_name").ok()?,
                row.try_get::<String, _>("right_name").ok()?,
            ))
        })
        .collect()
}

async fn load_weights(state: &AppState) -> MatchingWeights {
    if let Ok(Some(cached)) = state.redis.get("matching:config").await {
        if let Ok(value) = serde_json::from_str::<Value>(&cached) {
            return MatchingWeights::from_row(
                value["skill"].as_f64().unwrap_or(30.0) as f32,
                value["category"].as_f64().unwrap_or(25.0) as f32,
                value["distance"].as_f64().unwrap_or(15.0) as f32,
                value["employment"].as_f64().unwrap_or(10.0) as f32,
                value["salary"].as_f64().unwrap_or(10.0) as f32,
                value["experience"].as_f64().unwrap_or(5.0) as f32,
                value["availability"].as_f64().unwrap_or(5.0) as f32,
                value["semantic"].as_f64().unwrap_or(0.0) as f32,
            );
        }
    }
    let weights = match sqlx::query(
        r#"SELECT skill_weight, category_weight, distance_weight, employment_type_weight,
                  salary_weight, experience_weight, availability_weight, semantic_weight
           FROM matching_config WHERE id = 1"#,
    )
    .fetch_optional(&state.db)
    .await
    {
        Ok(Some(row)) => MatchingWeights::from_row(
            weight_col(&row, "skill_weight", 30.0),
            weight_col(&row, "category_weight", 25.0),
            weight_col(&row, "distance_weight", 15.0),
            weight_col(&row, "employment_type_weight", 10.0),
            weight_col(&row, "salary_weight", 10.0),
            weight_col(&row, "experience_weight", 5.0),
            weight_col(&row, "availability_weight", 5.0),
            weight_col(&row, "semantic_weight", 0.0),
        ),
        _ => MatchingWeights::default(),
    };
    let _ = state
        .redis
        .set(
            "matching:config",
            &json!({
                "skill": weights.skill,
                "category": weights.category,
                "distance": weights.distance,
                "employment": weights.employment_type,
                "salary": weights.salary,
                "experience": weights.experience,
                "availability": weights.availability,
                "semantic": weights.semantic,
            })
            .to_string(),
            300,
        )
        .await;
    weights
}

#[cfg(test)]
mod tests {
    use super::public_name;

    #[test]
    fn public_name_hides_surname() {
        assert_eq!(public_name("Rahul Sharma"), "Rahul S.");
    }

    #[test]
    fn candidate_card_has_no_contact_fields() {
        let value = serde_json::json!({
            "name": "Rahul S.",
            "matchScore": 90
        });
        assert!(value.get("phone").is_none());
        assert!(value.get("email").is_none());
        assert!(value.get("documentUrl").is_none());
    }
}
