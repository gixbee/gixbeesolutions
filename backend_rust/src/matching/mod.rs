use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::{HIRING_INTEREST_COLS, HIRING_REQUEST_COLS, JOB_PREFERENCE_COLS};

use rust_decimal::prelude::ToPrimitive;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

mod engine;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/preferences", get(list_preferences).post(create_preference))
        .route("/preferences/{id}", patch(update_preference).delete(delete_preference))
        .route("/catalog", get(catalog))
        .route("/pricing", get(pricing))
        .route("/credit", get(credit))
        .route("/estimate", get(estimate))
        .route("/offers", get(list_offers))
        .route("/offers/{request_id}/respond", post(respond_offer))
        .route("/requests", get(list_requests).post(create_request))
        .route("/requests/{id}", get(get_request))
        .route("/requests/{id}/resolve", post(resolve_request))
        .route("/interests/{id}/decision", patch(interest_decision))
}

async fn list_preferences(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE "userId" = $1"#
    ))
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(pref_json).collect()))
}

async fn create_preference(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO job_preferences (id, "userId", "jobType", "isActive") VALUES ($1, $2, $3, true)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("jobType").and_then(|v| v.as_str()).unwrap_or(""))
    .execute(&state.db)
    .await?;
    Ok(Json(pref_json(
        &sqlx::query(&format!(r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE id = $1"#))
            .bind(id)
            .fetch_one(&state.db)
            .await?,
    )))
}

async fn update_preference(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let pid = Uuid::parse_str(&id)?;
    if let Some(jt) = body.get("jobType").and_then(|v| v.as_str()) {
        sqlx::query(r#"UPDATE job_preferences SET "jobType" = $1 WHERE id = $2"#)
            .bind(jt)
            .bind(pid)
            .execute(&state.db)
            .await?;
    }
    let row = sqlx::query(&format!(r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE id = $1"#))
        .bind(pid)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(pref_json(&row)))
}

async fn delete_preference(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let pid = Uuid::parse_str(&id)?;
    sqlx::query(r#"DELETE FROM job_preferences WHERE id = $1"#)
        .bind(pid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "deleted": true })))
}

async fn catalog() -> Json<Value> {
    Json(json!({
        "employmentTypes": ["FULL_TIME", "PART_TIME", "CONTRACT"],
        "categories": [],
    }))
}

async fn pricing() -> Json<Value> {
    Json(json!({
        "tiers": [49, 99, 199, 399],
        "guaranteeHours": 24,
        "extraJobTypeFee": 50,
    }))
}

async fn credit(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let balance = sqlx::query_scalar::<_, rust_decimal::Decimal>(
        r#"SELECT "hiringCreditBalance" FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({ "balance": balance })))
}

#[derive(Deserialize)]
struct EstimateQuery {
    jobType: Option<String>,
    salary: Option<String>,
}

async fn estimate(Query(q): Query<EstimateQuery>) -> Json<Value> {
    Json(json!({
        "jobType": q.jobType,
        "fee": 49,
        "creditApplied": 0,
        "amountDue": 49,
    }))
}

async fn list_offers(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {HIRING_INTEREST_COLS} FROM hiring_interests WHERE "candidateId" = $1"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "requestId": r.get::<Uuid, _>("requestId").to_string(),
        "response": r.get::<String, _>("response"),
        "decision": r.get::<String, _>("decision"),
        "notifiedAt": r.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("notifiedAt").ok().flatten(),
    })).collect()))
}

#[derive(Deserialize)]
struct RespondBody {
    interested: bool,
}

async fn respond_offer(
    State(state): State<AppState>,
    user: AuthUser,
    Path(request_id): Path<String>,
    Json(body): Json<RespondBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rid = Uuid::parse_str(&request_id)?;

    let interest = sqlx::query(
        r#"SELECT hi.id, hi.response::text AS response, hr.status::text AS request_status
           FROM hiring_interests hi
           JOIN hiring_requests hr ON hr.id = hi."requestId"
           WHERE hi."requestId" = $1 AND hi."candidateId" = $2"#,
    )
    .bind(rid)
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("This offer was not sent to you".into()))?;

    if interest.get::<String, _>("response") != "PENDING" {
        return Err(AppError::BadRequest(
            "You have already responded to this offer".into(),
        ));
    }
    if interest.get::<String, _>("request_status") != "COLLECTING" {
        return Err(AppError::BadRequest(
            "This opening is no longer accepting responses".into(),
        ));
    }

    let response = if body.interested {
        "INTERESTED"
    } else {
        "NOT_INTERESTED"
    };
    sqlx::query(
        r#"UPDATE hiring_interests SET response = $1, "respondedAt" = NOW()
           WHERE "requestId" = $2 AND "candidateId" = $3"#,
    )
    .bind(response)
    .bind(rid)
    .bind(uid)
    .execute(&state.db)
    .await?;

    if body.interested {
        engine::maybe_deliver_on_response(&state, rid).await?;
    }

    Ok(Json(json!({ "response": response })))
}

async fn list_requests(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE "employerId" = $1"#
    ))
        .bind(uid)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows.iter().map(request_json).collect()))
}

async fn create_request(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO hiring_requests (id, "employerId", "jobType", status, "feeAmount", "deadlineAt")
           VALUES ($1, $2, $3, 'COLLECTING', 49, NOW() + INTERVAL '24 hours')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("jobType").and_then(|v| v.as_str()).unwrap_or(""))
    .execute(&state.db)
    .await?;
    engine::schedule_hiring_engine(state.clone(), id.to_string());
    get_request(State(state), Path(id.to_string())).await
}

async fn get_request(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE id = $1"#))
        .bind(rid)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("Request not found".into()))?;
    Ok(Json(request_json(&row)))
}

#[derive(Deserialize)]
struct ResolveBody {
    choice: String,
}

async fn resolve_request(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ResolveBody>,
) -> AppResult<Json<Value>> {
    let choice = if body.choice.to_uppercase() == "REFUND" {
        "REFUND"
    } else {
        "CREDIT"
    };
    let row = engine::resolve_guarantee(&state, &user.user_id, &id, choice).await?;
    Ok(Json(request_json(&row)))
}

#[derive(Deserialize)]
struct DecisionBody {
    decision: String,
}

async fn interest_decision(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<DecisionBody>,
) -> AppResult<Json<Value>> {
    let iid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE hiring_interests SET decision = $1 WHERE id = $2"#)
        .bind(&body.decision)
        .bind(iid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "status": body.decision })))
}

fn pref_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "jobType": row.get::<String, _>("jobType"),
        "skills": row.try_get::<Option<Vec<String>>, _>("skills").ok().flatten(),
        "preferredLocation": row.get::<Option<String>, _>("preferredLocation"),
        "expectedSalary": row.try_get::<rust_decimal::Decimal, _>("expectedSalary").ok(),
        "salaryNegotiable": row.get::<bool, _>("salaryNegotiable"),
        "employmentType": row.get::<Option<String>, _>("employmentType"),
        "experienceYears": row.get::<i32, _>("experienceYears"),
        "noticePeriod": row.get::<String, _>("noticePeriod"),
        "isActive": row.get::<bool, _>("isActive"),
        "isPaid": row.get::<bool, _>("isPaid"),
        "paidUntil": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("paidUntil").ok().flatten(),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
    })
}

fn request_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "jobType": row.get::<String, _>("jobType"),
        "status": row.get::<String, _>("status"),
        "feeAmount": row.try_get::<rust_decimal::Decimal, _>("feeAmount").ok(),
        "deadlineAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("deadlineAt").ok(),
        "vacancies": row.get::<i32, _>("vacancies"),
        "location": row.get::<Option<String>, _>("location"),
    })
}

pub fn fee_for_vacancies(vacancies: i32) -> AppResult<i32> {
    let v = vacancies.max(1);
    if v <= 1 {
        Ok(49)
    } else if v <= 5 {
        Ok(99)
    } else if v <= 10 {
        Ok(199)
    } else if v <= 25 {
        Ok(399)
    } else {
        Err(AppError::BadRequest(
            "Maximum 25 vacancies per hiring request".into(),
        ))
    }
}

async fn assert_verified_hiring_business(state: &AppState, employer_id: &str) -> AppResult<()> {
    let uid = Uuid::parse_str(employer_id)?;
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*)::bigint FROM businesses
           WHERE "ownerId" = $1 AND type::text = 'HIRING' AND status::text = 'VERIFIED'"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if count < 1 {
        return Err(AppError::BadRequest(
            "A verified Hiring business is required before you can run Smart Hiring.".into(),
        ));
    }
    Ok(())
}

pub async fn quote_match_fee(
    state: &AppState,
    employer_id: &str,
    vacancies: i32,
) -> AppResult<(i32, i32, i32)> {
    assert_verified_hiring_business(state, employer_id).await?;
    let fee = fee_for_vacancies(vacancies.max(1))?;
    let uid = Uuid::parse_str(employer_id)?;
    let credit: rust_decimal::Decimal = sqlx::query_scalar(
        r#"SELECT "hiringCreditBalance" FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    let credit_i = credit
        .to_i32()
        .unwrap_or(0)
        .max(0);
    let credit_applied = credit_i.min(fee);
    let amount_due = fee - credit_applied;
    Ok((fee, credit_applied, amount_due))
}

pub async fn preference_count(state: &AppState, user_id: &str) -> AppResult<i64> {
    let uid = Uuid::parse_str(user_id)?;
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*)::bigint FROM job_preferences WHERE "userId" = $1 AND "isActive" = true"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    Ok(count)
}

pub async fn create_request_from_payment(
    state: &AppState,
    employer_id: &str,
    meta: &Value,
    payment_order_id: Uuid,
    razorpay_payment_id: Option<&str>,
) -> AppResult<()> {
    assert_verified_hiring_business(state, employer_id).await?;
    let employer = Uuid::parse_str(employer_id)?;
    let job_type = meta
        .get("jobType")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if job_type.is_empty() {
        return Err(AppError::BadRequest("jobType is required".into()));
    }
    let vacancies = meta
        .get("vacancies")
        .and_then(|v| v.as_i64())
        .unwrap_or(1)
        .max(1) as i32;
    let fee = meta.get("fee").and_then(|v| v.as_i64()).unwrap_or(0) as i32;
    let credit_applied = meta
        .get("creditApplied")
        .and_then(|v| v.as_i64())
        .unwrap_or(0) as i32;
    let skills: Vec<String> = meta
        .get("skills")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.trim().to_string()))
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();
    let location = meta.get("location").and_then(|v| v.as_str());
    let salary_offered = meta
        .get("salaryOffered")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let salary_min = meta.get("salaryMin").and_then(|v| v.as_f64()).unwrap_or(0.0);
    let salary_max = meta
        .get("salaryMax")
        .and_then(|v| v.as_f64())
        .unwrap_or(salary_offered);
    let salary_negotiable = meta
        .get("salaryNegotiable")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let employment_type = meta
        .get("employmentType")
        .and_then(|v| v.as_str())
        .unwrap_or("FULL_TIME");
    let experience_min = meta
        .get("experienceMinYears")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .max(0) as i32;
    let target_interested = vacancies * 3;
    let fee_dec = rust_decimal::Decimal::from(fee);
    let credit_dec = rust_decimal::Decimal::from(credit_applied);

    let mut tx = state.db.begin().await?;
    if credit_applied > 0 {
        sqlx::query(
            r#"UPDATE users SET "hiringCreditBalance" = GREATEST("hiringCreditBalance" - $1, 0)
               WHERE id = $2"#,
        )
        .bind(credit_dec)
        .bind(employer)
        .execute(&mut *tx)
        .await?;
    }

    let request_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO hiring_requests (
            id, "employerId", "jobType", skills, location, "salaryOffered", "salaryMin", "salaryMax",
            "salaryNegotiable", "employmentType", "experienceMinYears", vacancies, "targetInterested",
            "feeAmount", "creditApplied", "paymentOrderId", "razorpayPaymentId", status, "deadlineAt"
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, 'COLLECTING',
            NOW() + INTERVAL '24 hours'
        )"#,
    )
    .bind(request_id)
    .bind(employer)
    .bind(job_type)
    .bind(&skills)
    .bind(location)
    .bind(salary_offered)
    .bind(salary_min)
    .bind(salary_max)
    .bind(salary_negotiable)
    .bind(employment_type)
    .bind(experience_min)
    .bind(vacancies)
    .bind(target_interested)
    .bind(fee_dec)
    .bind(credit_dec)
    .bind(payment_order_id)
    .bind(razorpay_payment_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    engine::schedule_hiring_engine(state.clone(), request_id.to_string());
    Ok(())
}

pub async fn create_preference_from_payment(
    state: &AppState,
    user_id: &str,
    meta: &Value,
) -> AppResult<()> {
    let uid = Uuid::parse_str(user_id)?;
    let job_type = meta
        .get("jobType")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    if job_type.is_empty() {
        return Err(AppError::BadRequest("jobType is required".into()));
    }

    let existing: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM job_preferences
           WHERE "userId" = $1 AND LOWER("jobType") = LOWER($2) AND "isActive" = true LIMIT 1"#,
    )
    .bind(uid)
    .bind(job_type)
    .fetch_optional(&state.db)
    .await?;
    if existing.is_some() {
        return Ok(());
    }

    let skills: Vec<String> = meta
        .get("skills")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.trim().to_string()))
                .filter(|s| !s.is_empty())
                .collect()
        })
        .unwrap_or_default();
    let preferred_location = meta.get("preferredLocation").and_then(|v| v.as_str());
    let expected_salary = meta
        .get("expectedSalary")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let salary_negotiable = meta
        .get("salaryNegotiable")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let employment_type = meta
        .get("employmentType")
        .and_then(|v| v.as_str())
        .unwrap_or("FULL_TIME");
    let experience_years = meta
        .get("experienceYears")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .max(0) as i32;
    let notice_period = meta
        .get("noticePeriod")
        .and_then(|v| v.as_str())
        .unwrap_or("IMMEDIATE");

    sqlx::query(
        r#"INSERT INTO job_preferences (
            id, "userId", "jobType", skills, "preferredLocation", "expectedSalary",
            "salaryNegotiable", "employmentType", "experienceYears", "noticePeriod",
            "isActive", "isPaid", "paidUntil"
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true, true, NOW() + INTERVAL '30 days')"#,
    )
    .bind(Uuid::new_v4())
    .bind(uid)
    .bind(job_type)
    .bind(&skills)
    .bind(preferred_location)
    .bind(expected_salary)
    .bind(salary_negotiable)
    .bind(employment_type)
    .bind(experience_years)
    .bind(notice_period)
    .execute(&state.db)
    .await?;
    Ok(())
}
