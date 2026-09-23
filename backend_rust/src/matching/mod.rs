use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::{HIRING_REQUEST_COLS, JOB_PREFERENCE_COLS};

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;
use rust_decimal::prelude::ToPrimitive;

mod engine;
mod flow;
mod profiles;
mod progress;
pub use engine::{process_refund, run_scheduler};
#[cfg(test)]
pub async fn poll_for_tests(state: &AppState) -> AppResult<()> {
    engine::poll_due(state).await
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route(
            "/preferences",
            get(list_preferences).post(create_preference),
        )
        .route(
            "/preferences/{id}",
            patch(update_preference).delete(delete_preference),
        )
        .route("/catalog", get(catalog))
        .route("/pricing", get(pricing))
        .route("/credit", get(credit))
        .route("/estimate", get(estimate))
        .route("/offers", get(list_offers))
        .route("/offers/{request_id}/respond", post(respond_offer))
        .route("/requests", get(list_requests).post(create_request))
        .route("/requests/{id}", get(get_request))
        .route("/requests/{id}/close", post(close_request))
        .route("/requests/{id}/resolve", post(resolve_request))
        .route("/interests/{id}/decision", patch(interest_decision))
        .route("/interests/{id}/progress", get(progress::detail))
        .route("/interests/{id}/progress/{action}", post(progress::action))
}

async fn list_preferences(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE "userId" = $1 AND "isActive" = true ORDER BY "createdAt" ASC"#
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
    Ok(Json(
        profiles::create(&state, &user.user_id, &body, false,None).await?,
    ))
}

async fn update_preference(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    Ok(Json(
        profiles::update(&state, &user.user_id, &id, &body).await?,
    ))
}

async fn delete_preference(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    profiles::delete(&state, &user.user_id, &id).await?;
    Ok(Json(json!({ "deleted": true })))
}

async fn catalog() -> Json<Value> {
    Json(json!({
        "employmentTypes": [{"code":"FT","label":"Full Time"},{"code":"PT","label":"Part Time"},{"code":"INTERN","label":"Intern"},{"code":"CONTRACT","label":"Contract"}],
        "categories": ["Electrician","Plumbing","Cleaning","Painting","Carpentry","AC & Appliances","Driving","Delivery","Cooking","Security","Retail & Sales","Office / Admin","Tech & IT","Teaching","Healthcare","Events","Fitness & Yoga","Beauty"],
    }))
}

async fn pricing() -> Json<Value> {
    Json(json!({
        "tiers": [{"maxVacancies":1,"fee":49},{"maxVacancies":5,"fee":99},{"maxVacancies":10,"fee":199},{"maxVacancies":25,"fee":399}],
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
#[serde(rename_all = "camelCase")]
struct EstimateQuery {
    job_type: Option<String>,
    salary: Option<String>,
    salary_min: Option<String>,
    salary_max: Option<String>,
    salary_negotiable: Option<String>,
    employment_type: Option<String>,
    location: Option<String>,
    experience_min: Option<i32>,
    skills: Option<String>,
}

async fn estimate(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<EstimateQuery>,
) -> AppResult<Json<Value>> {
    let number = |value: Option<&str>| -> AppResult<f64> {
        let value = value
            .unwrap_or("0")
            .parse::<f64>()
            .map_err(|_| AppError::BadRequest("Invalid salary".into()))?;
        if !value.is_finite() || !(0.0..=99_999_999.0).contains(&value) {
            return Err(AppError::BadRequest("Invalid salary".into()));
        }
        Ok(value)
    };
    let salary = engine::EmployerSalary {
        salary_min: number(q.salary_min.as_deref())?,
        salary_max: number(q.salary_max.as_deref().or(q.salary.as_deref()))?,
        salary_negotiable: matches!(q.salary_negotiable.as_deref(), Some("true" | "1")),
    };
    if salary.salary_min > salary.salary_max {
        return Err(AppError::BadRequest(
            "Salary minimum exceeds maximum".into(),
        ));
    }
    let employment = profiles::employment_type(q.employment_type.as_deref())?;
    let skills = q
        .skills
        .unwrap_or_default()
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect::<Vec<_>>();
    let matches = engine::find_matching_preferences(
        &state,
        q.job_type.as_deref().unwrap_or(""),
        &salary,
        employment.as_deref(),
        q.location.as_deref(),
        q.experience_min.unwrap_or(0),
        &skills,
        Uuid::parse_str(&user.user_id)?,
        &[],
        i32::MAX,
    )
    .await?;
    Ok(Json(json!({"estimated":matches.len()})))
}

async fn list_offers(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT hi.id, hi."requestId", hi.response::text AS response, hi.decision::text AS decision, hi."notifiedAt",
        hi.progress, hr."employerId", hr."jobType", hr.location, hr."salaryOffered", hr."salaryMin", hr."salaryMax", hr."salaryNegotiable",
        hr."employmentType"::text AS "employmentType", hr.skills, b.name AS "businessName",
        (hr.status::text = 'COLLECTING' AND hr."deadlineAt" > NOW() AND hi.response::text = 'PENDING') AS open
        FROM hiring_interests hi JOIN hiring_requests hr ON hr.id = hi."requestId"
        LEFT JOIN businesses b ON b.id = hr."businessId"
        WHERE hi."candidateId" = $1 ORDER BY hi."notifiedAt" DESC"#)
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| {
        let progress: Value = r.try_get("progress").ok().unwrap_or(json!({}));
        let response = r.get::<String, _>("response");
        let decision = r.get::<String, _>("decision");
        json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "requestId": r.get::<Uuid, _>("requestId").to_string(),
        "employerId": r.get::<Uuid, _>("employerId").to_string(),
        "response": response,
        "decision": decision,
        "pipelineStage": flow::pipeline_label(&response, &decision, &progress),
        "canChat": flow::can_chat(&response, &decision),
        "invited": progress.get("invited").and_then(Value::as_bool).unwrap_or(false),
        "contactRequested": progress.get("contactRequested").and_then(Value::as_bool).unwrap_or(false),
        "contactShared": progress.get("contactShared").and_then(Value::as_bool).unwrap_or(false),
        "notifiedAt": crate::common::pg::date_json(r, "notifiedAt"),
        "jobType": r.get::<String, _>("jobType"), "location": r.get::<Option<String>, _>("location"),
        "businessName": r.get::<Option<String>, _>("businessName"),
        "salaryOffered": r.get::<rust_decimal::Decimal, _>("salaryOffered").to_f64(),
        "salaryMin": r.get::<rust_decimal::Decimal, _>("salaryMin").to_f64(),
        "salaryMax": r.get::<rust_decimal::Decimal, _>("salaryMax").to_f64(),
        "salaryNegotiable": r.get::<bool, _>("salaryNegotiable"), "employmentType": r.get::<Option<String>, _>("employmentType"),
        "skills": crate::common::pg::string_list(r, "skills"), "open": r.get::<bool, _>("open"),
    })}).collect()))
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

    let mut tx = state.db.begin().await?;
    let interest = sqlx::query(
        r#"SELECT hi.id, hi.response::text AS response, hr.status::text AS request_status, hr."deadlineAt" > NOW() AS open
           FROM hiring_interests hi
           JOIN hiring_requests hr ON hr.id = hi."requestId"
           WHERE hi."requestId" = $1 AND hi."candidateId" = $2 FOR UPDATE OF hr, hi"#,
    )
    .bind(rid)
    .bind(uid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("This offer was not sent to you".into()))?;

    if interest.get::<String, _>("response") != "PENDING" {
        return Err(AppError::BadRequest(
            "You have already responded to this offer".into(),
        ));
    }
    if interest.get::<String, _>("request_status") != "COLLECTING"
        || !interest.get::<bool, _>("open")
    {
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
        r#"UPDATE hiring_interests SET response = $1::hiring_interests_response_enum, "respondedAt" = NOW(), "updatedAt" = NOW(),
           progress = COALESCE(progress, '{}'::jsonb) || CASE WHEN $1 = 'INTERESTED'
             THEN jsonb_build_object('mutualInterest', true, 'stage', 'CHATTING')
             ELSE '{}'::jsonb END
           WHERE "requestId" = $2 AND "candidateId" = $3"#,
    )
    .bind(response)
    .bind(rid)
    .bind(uid)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    if body.interested {
        engine::maybe_deliver_on_response(&state, rid).await?;
    }

    Ok(Json(json!({ "response": response })))
}

async fn list_requests(
    State(state): State<AppState>,
    user: AuthUser,
    Query(filter):Query<RequestFilter>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE "employerId" = $1 AND ($2::uuid IS NULL OR "businessId"=$2) ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .bind(uid)
    .bind(filter.business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(request_json).collect()))
}

async fn create_request(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    validate_request(&body)?;
    let business=resolve_business(&state,&user.user_id,&body).await?;
    let vacancies = body.get("vacancies").and_then(Value::as_i64).unwrap_or(1) as i32;
    let (fee, credit_applied, amount_due) =
        quote_match_fee(&state, &user.user_id, vacancies).await?;
    if amount_due > 0 {
        return Ok(Json(
            json!({"needsPayment":true,"fee":fee,"creditApplied":credit_applied,"amountDue":amount_due}),
        ));
    }
    let mut meta = body;
    meta["businessId"]=json!(business);
    meta["fee"] = json!(fee);
    meta["creditApplied"] = json!(credit_applied);
    let id = start_request(&state, &user.user_id, &meta, None, None).await?;
    let Json(request) = get_request(State(state), user, Path(id.to_string())).await?;
    Ok(Json(json!({"request":request})))
}

async fn get_request(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE id = $1 AND "employerId" = $2"#
    ))
    .bind(rid)
    .bind(Uuid::parse_str(&user.user_id)?)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Request not found".into()))?;
    let mut result = request_json(&row);
    let job_skills = crate::common::pg::string_list(&row, "skills");
    let job_loc = row
        .get::<Option<String>, _>("location")
        .unwrap_or_default()
        .to_lowercase();
    let job_emp = row.get::<Option<String>, _>("employmentType");
    let job_exp = row.get::<i32, _>("experienceMinYears");
    let salary_offered = row.get::<rust_decimal::Decimal, _>("salaryOffered");
    let salary_max_raw = row.get::<rust_decimal::Decimal, _>("salaryMax");
    let salary_max = if salary_max_raw > rust_decimal::Decimal::ZERO {
        salary_max_raw
    } else {
        salary_offered
    };
    let candidates = sqlx::query(r#"SELECT hi.id, hi."candidateId", hi.response::text AS response, hi.decision::text AS decision,
        hi."respondedAt", hi.progress, u.name, u."phoneNumber" AS phone,
        p.skills, p."expectedSalary", p."experienceYears", p."noticePeriod"::text AS "noticePeriod",
        p."preferredLocation", p."employmentType"::text AS "prefEmployment"
        FROM hiring_interests hi JOIN users u ON u.id = hi."candidateId"
        LEFT JOIN job_preferences p ON p.id = hi."preferenceId"
        WHERE hi."requestId" = $1 ORDER BY hi."notifiedAt" ASC"#)
        .bind(rid).fetch_all(&state.db).await?;
    let notified: i64 =
        sqlx::query_scalar(r#"SELECT COUNT(*) FROM hiring_interests WHERE "requestId" = $1"#)
            .bind(rid)
            .fetch_one(&state.db)
            .await?;
    let hired: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM hiring_interests WHERE "requestId"=$1 AND decision='HIRED'"#,
    )
    .bind(rid)
    .fetch_one(&state.db)
    .await?;
    let vacancies = row.get::<i32, _>("vacancies");
    let filled = hired >= i64::from(vacancies.max(1));
    let status = row.get::<String, _>("status");
    result["notifiedCount"] = json!(notified);
    let refund_status: Option<String> = sqlx::query_scalar(r#"SELECT status FROM outbox_events WHERE "aggregateId"=$1 AND type='hiring.refund' LIMIT 1"#)
        .bind(rid).fetch_optional(&state.db).await?;
    result["refundStatus"] = json!(refund_status);
    result["filled"] = json!(filled);
    result["jobStatus"] = json!(if status == "CLOSED" {
        "CLOSED"
    } else if filled {
        "FILLED"
    } else if status == "COLLECTING" {
        "LIVE"
    } else {
        status.as_str()
    });
    let mapped: Vec<Value> = candidates
        .iter()
        .map(|r| {
            let progress: Value = r.try_get("progress").ok().unwrap_or(json!({}));
            let response = r.get::<String, _>("response");
            let decision = r.get::<String, _>("decision");
            let unlocked = flow::contact_unlocked(&progress, &decision);
            let cand_skills = crate::common::pg::string_list(r, "skills");
            let overlap = flow::skill_overlap(&job_skills, &cand_skills);
            let loc = r
                .get::<Option<String>, _>("preferredLocation")
                .unwrap_or_default()
                .to_lowercase();
            let salary_hit = r
                .get::<Option<rust_decimal::Decimal>, _>("expectedSalary")
                .map(|s| s <= salary_max)
                .unwrap_or(true);
            let exp_hit = r
                .get::<Option<i32>, _>("experienceYears")
                .map(|y| y >= job_exp)
                .unwrap_or(true);
            let emp = r.get::<Option<String>, _>("prefEmployment");
            json!({
                "interestId": r.get::<Uuid, _>("id").to_string(),
                "candidateId": r.get::<Uuid, _>("candidateId").to_string(),
                "name": r.get::<Option<String>, _>("name"),
                "phone": if unlocked { json!(r.get::<Option<String>, _>("phone")) } else { Value::Null },
                "phoneLocked": !unlocked,
                "emailLocked": !unlocked,
                "response": response,
                "decision": decision,
                "pipelineStage": flow::pipeline_label(&response, &decision, &progress),
                "canChat": flow::can_chat(&response, &decision),
                "invited": progress.get("invited").and_then(Value::as_bool).unwrap_or(false),
                "contactRequested": progress.get("contactRequested").and_then(Value::as_bool).unwrap_or(false),
                "contactShared": progress.get("contactShared").and_then(Value::as_bool).unwrap_or(false),
                "respondedAt": crate::common::pg::date_json(r, "respondedAt"),
                "skills": cand_skills,
                "expectedSalary": r.get::<Option<rust_decimal::Decimal>, _>("expectedSalary"),
                "experienceYears": r.get::<Option<i32>, _>("experienceYears"),
                "noticePeriod": r.get::<Option<String>, _>("noticePeriod"),
                "preferredLocation": r.get::<Option<String>, _>("preferredLocation"),
                "matchReasons": flow::match_reasons(
                    true,
                    &overlap,
                    !job_loc.is_empty() && loc.contains(&job_loc),
                    salary_hit,
                    job_emp.is_some() && emp == job_emp,
                    exp_hit,
                ),
            })
        })
        .collect();
    result["interestedCount"] = json!(mapped.iter().filter(|c| c["response"] == "INTERESTED").count());
    result["candidates"] = json!(mapped);
    Ok(Json(result))
}

async fn close_request(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let updated = sqlx::query(
        r#"UPDATE hiring_requests SET status='CLOSED'::hiring_requests_status_enum, "updatedAt"=NOW()
           WHERE id=$1 AND "employerId"=$2 AND status::text IN ('COLLECTING','DELIVERED')
           RETURNING id"#,
    )
    .bind(rid)
    .bind(uid)
    .fetch_optional(&state.db)
    .await?;
    if updated.is_none() {
        return Err(AppError::BadRequest(
            "This job cannot be closed in its current status".into(),
        ));
    }
    get_request(State(state), user, Path(id)).await
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
    let row = engine::resolve_guarantee(&state, &user.user_id, &id, &body.choice).await?;
    Ok(Json(request_json(&row)))
}

#[derive(Deserialize)]
struct DecisionBody {
    decision: String,
}

async fn interest_decision(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<DecisionBody>,
) -> AppResult<Json<Value>> {
    let iid = Uuid::parse_str(&id)?;
    if body.decision=="HIRED" {
        return Err(AppError::Conflict("Hiring completes after the candidate accepts an offer and both participants confirm joining".into()));
    }
    if !matches!(body.decision.as_str(), "SHORTLISTED" | "REJECTED" | "HIRED") {
        return Err(AppError::BadRequest(
            "Decision must be SHORTLISTED, REJECTED or HIRED".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let changed = sqlx::query(r#"UPDATE hiring_interests hi SET decision = $1::hiring_interests_decision_enum, "updatedAt" = NOW(),
        progress = COALESCE(hi.progress, '{}'::jsonb) || CASE
            WHEN $1 = 'SHORTLISTED' THEN jsonb_build_object('stage', 'SHORTLISTED')
            WHEN $1 = 'REJECTED' THEN jsonb_build_object('stage', 'NOT_SELECTED')
            ELSE '{}'::jsonb END
        FROM hiring_requests hr WHERE hi.id = $2 AND hr.id = hi."requestId" AND hr."employerId" = $3
        AND hi.response::text = 'INTERESTED' AND hr.status::text IN ('COLLECTING', 'DELIVERED')
        AND (hi.decision::text = $1 OR hi.decision::text = 'PENDING' AND $1 IN ('SHORTLISTED','REJECTED')
             OR hi.decision::text = 'SHORTLISTED' AND $1 IN ('HIRED','REJECTED'))
        RETURNING hi."candidateId", hi."requestId""#)
        .bind(&body.decision)
        .bind(iid)
        .bind(Uuid::parse_str(&user.user_id)?)
        .fetch_optional(&mut *tx)
        .await?;
    let changed = changed.ok_or_else(|| {
        AppError::BadRequest("Candidate is unavailable or this decision is not allowed".into())
    })?;
    crate::outbox::notify(&mut tx,changed.get("requestId"),changed.get("candidateId"),"Hiring status update",
        &format!("Your application status is now {}.",body.decision.to_lowercase()),
        json!({"type":"hiring_status","requestId":changed.get::<Uuid,_>("requestId"),"decision":body.decision})).await?;
    tx.commit().await?;
    Ok(Json(json!({ "status": body.decision })))
}

fn pref_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "jobType": row.get::<String, _>("jobType"),
        "skills": crate::common::pg::string_list(row, "skills"),
        "preferredLocation": row.get::<Option<String>, _>("preferredLocation"),
        "expectedSalary": row.try_get::<rust_decimal::Decimal, _>("expectedSalary").ok(),
        "salaryNegotiable": row.get::<bool, _>("salaryNegotiable"),
        "employmentType": row.get::<Option<String>, _>("employmentType"),
        "experienceYears": row.get::<i32, _>("experienceYears"),
        "noticePeriod": row.get::<String, _>("noticePeriod"),
        "isActive": row.get::<bool, _>("isActive"),
        "isPaid": row.get::<bool, _>("isPaid"),
        "paidUntil": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("paidUntil").ok().flatten(),
        "createdAt": crate::common::pg::date_json(row, "createdAt"),
    })
}

fn request_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "businessId":row.get::<Option<Uuid>,_>("businessId"),
        "id": row.get::<Uuid, _>("id").to_string(),
        "jobType": row.get::<String, _>("jobType"),
        "status": row.get::<String, _>("status"),
        "feeAmount": row.try_get::<rust_decimal::Decimal, _>("feeAmount").ok(),
        "deadlineAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("deadlineAt").ok(),
        "vacancies": row.get::<i32, _>("vacancies"),
        "location": row.get::<Option<String>, _>("location"),
        "skills": crate::common::pg::string_list(row, "skills"),
        "salaryOffered": row.get::<rust_decimal::Decimal, _>("salaryOffered").to_f64(),
        "salaryMin": row.get::<rust_decimal::Decimal, _>("salaryMin").to_f64(),
        "salaryMax": row.get::<rust_decimal::Decimal, _>("salaryMax").to_f64(),
        "salaryNegotiable": row.get::<bool, _>("salaryNegotiable"),
        "employmentType": row.get::<Option<String>, _>("employmentType"),
        "experienceMinYears": row.get::<i32, _>("experienceMinYears"),
        "targetInterested": row.get::<i32, _>("targetInterested"),
        "creditApplied": row.get::<rust_decimal::Decimal, _>("creditApplied").to_f64(),
        "createdAt": crate::common::pg::date_json(row, "createdAt"),
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

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct RequestFilter {business_id:Option<Uuid>}

pub fn validate_preference(meta:&Value)->AppResult<()> {profiles::Preference::parse(meta)?;Ok(())}

pub async fn resolve_business(state:&AppState,owner:&str,meta:&Value)->AppResult<Uuid> {
    let chosen=meta.get("businessId").and_then(Value::as_str).map(Uuid::parse_str).transpose()?;
    let ids=sqlx::query_scalar::<_,Uuid>(r#"SELECT id FROM businesses WHERE "ownerId"=$1 AND type='HIRING' AND status='VERIFIED'
        AND ($2::uuid IS NULL OR id=$2) ORDER BY "createdAt" LIMIT 2"#)
        .bind(Uuid::parse_str(owner)?).bind(chosen).fetch_all(&state.db).await?;
    if ids.len()!=1 {return Err(AppError::BadRequest("Select the verified hiring business for this request".into()));}Ok(ids[0])
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
    let credit: rust_decimal::Decimal =
        sqlx::query_scalar(r#"SELECT "hiringCreditBalance" FROM users WHERE id = $1"#)
            .bind(uid)
            .fetch_one(&state.db)
            .await?;
    let reserved = reserved_hiring_credit(&state.db, uid, None).await?;
    let credit_i = (credit - reserved).to_i32().unwrap_or(0).max(0);
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
    start_request(
        state,
        employer_id,
        meta,
        Some(payment_order_id),
        razorpay_payment_id,
    )
    .await?;
    Ok(())
}

pub async fn reserved_hiring_credit<'e, E>(
    executor: E,
    user_id: Uuid,
    except: Option<Uuid>,
) -> Result<rust_decimal::Decimal, sqlx::Error>
where
    E: sqlx::Executor<'e, Database = sqlx::Postgres>,
{
    sqlx::query_scalar(r#"SELECT COALESCE(SUM(COALESCE((p.meta->>'creditApplied')::numeric,0)),0)
        FROM payment_orders p WHERE p."userId"=$1 AND p.purpose::text='HIRING_MATCH_FEE' AND p.status::text='CREATED'
        AND ($2::uuid IS NULL OR p.id<>$2)
        AND NOT EXISTS(SELECT 1 FROM hiring_requests hr WHERE hr."paymentOrderId"=p.id)"#)
        .bind(user_id).bind(except).fetch_one(executor).await
}

pub fn validate_request(meta: &Value) -> AppResult<()> {
    profiles::Preference::parse(&json!({
        "jobType": meta.get("jobType"), "skills": meta.get("skills").cloned().unwrap_or(json!([])),
        "expectedSalary": meta.get("salaryMax").or_else(||meta.get("salaryOffered")).cloned().unwrap_or(json!(0)),
        "employmentType": meta.get("employmentType"),
        "experienceYears": meta.get("experienceMinYears").cloned().unwrap_or(json!(0))
    }))?;
    let vacancies = meta.get("vacancies").and_then(Value::as_i64).unwrap_or(1);
    if !(1..=25).contains(&vacancies) {
        return Err(AppError::BadRequest(
            "Vacancies must be between 1 and 25".into(),
        ));
    }
    let min = meta.get("salaryMin").and_then(Value::as_f64).unwrap_or(0.0);
    let max = meta
        .get("salaryMax")
        .or_else(|| meta.get("salaryOffered"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    if min < 0.0 || max <= 0.0 || min > max {
        return Err(AppError::BadRequest(
            "Provide a positive salary maximum and a valid salary range".into(),
        ));
    }
    Ok(())
}

async fn start_request(
    state: &AppState,
    employer_id: &str,
    meta: &Value,
    payment_order_id: Option<Uuid>,
    razorpay_payment_id: Option<&str>,
) -> AppResult<Uuid> {
    validate_request(meta)?;
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
    let salary_min = meta
        .get("salaryMin")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let salary_max = meta
        .get("salaryMax")
        .and_then(|v| v.as_f64())
        .unwrap_or(salary_offered);
    let salary_negotiable = meta
        .get("salaryNegotiable")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    let employment_type =
        profiles::employment_type(meta.get("employmentType").and_then(Value::as_str))?;
    let experience_min = meta
        .get("experienceMinYears")
        .and_then(|v| v.as_i64())
        .unwrap_or(0)
        .max(0) as i32;
    let target_interested = vacancies * 3;
    let fee_dec = rust_decimal::Decimal::from(fee);
    let credit_dec = rust_decimal::Decimal::from(credit_applied);

    let mut tx = state.db.begin().await?;
    let balance: rust_decimal::Decimal =
        sqlx::query_scalar(r#"SELECT "hiringCreditBalance" FROM users WHERE id = $1 FOR UPDATE"#)
            .bind(employer)
            .fetch_one(&mut *tx)
            .await?;
    if let Some(payment_id) = payment_order_id {
        if let Some(existing) = sqlx::query_scalar::<_, Uuid>(
            r#"SELECT id FROM hiring_requests WHERE "paymentOrderId" = $1"#,
        )
        .bind(payment_id)
        .fetch_optional(&mut *tx)
        .await?
        {
            return Ok(existing);
        }
    }
    let business=resolve_business(state,employer_id,meta).await?;
    let other_reserved = reserved_hiring_credit(&mut *tx, employer, payment_order_id).await?;
    if fee != fee_for_vacancies(vacancies)?
        || credit_applied < 0
        || credit_applied > fee
        || balance - other_reserved < credit_dec
    {
        return Err(AppError::Conflict(
            "Hiring credit changed; request could not be funded".into(),
        ));
    }
    if payment_order_id.is_none() && credit_applied != fee {
        return Err(AppError::BadRequest(
            "Payment is required before matching starts".into(),
        ));
    }
    if credit_applied > 0 {
        sqlx::query(
            r#"UPDATE users SET "hiringCreditBalance" = "hiringCreditBalance" - $1
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
            "feeAmount", "creditApplied", "paymentOrderId", "razorpayPaymentId", status, "deadlineAt", "businessId"
        ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10::hiring_requests_employmenttype_enum, $11, $12, $13, $14, $15, $16, $17, 'COLLECTING',
            NOW() + INTERVAL '24 hours', $18
        )"#,
    )
    .bind(request_id)
    .bind(employer)
    .bind(job_type)
    .bind(skills.join(","))
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
    .bind(business)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    engine::schedule_hiring_engine(state.clone(), request_id.to_string());
    Ok(request_id)
}

pub async fn create_preference_from_payment(
    state: &AppState,
    user_id: &str,
    meta: &Value,
    payment_id:Uuid,
) -> AppResult<()> {
    profiles::create(state, user_id, meta, true,Some(payment_id)).await?;
    Ok(())
}
