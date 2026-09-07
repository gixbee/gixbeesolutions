use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, patch, post},
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
    let rows = sqlx::query(r#"SELECT * FROM job_preferences WHERE "userId" = $1"#)
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
        r#"INSERT INTO job_preferences (id, "userId", "jobType", status) VALUES ($1, $2, $3, 'ACTIVE')"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("jobType").and_then(|v| v.as_str()).unwrap_or(""))
    .execute(&state.db)
    .await?;
    Ok(Json(pref_json(
        &sqlx::query(r#"SELECT * FROM job_preferences WHERE id = $1"#)
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
    let row = sqlx::query(r#"SELECT * FROM job_preferences WHERE id = $1"#)
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
    let rows = sqlx::query(
        r#"SELECT * FROM hiring_interests WHERE "candidateId" = $1"#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| json!({
        "id": r.get::<Uuid, _>("id").to_string(),
        "requestId": r.get::<Uuid, _>("requestId").to_string(),
        "status": r.get::<String, _>("status"),
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
    let status = if body.interested { "INTERESTED" } else { "DECLINED" };
    sqlx::query(
        r#"INSERT INTO hiring_interests (id, "requestId", "candidateId", status) VALUES ($1, $2, $3, $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(rid)
    .bind(uid)
    .bind(status)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "status": status })))
}

async fn list_requests(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(r#"SELECT * FROM hiring_requests WHERE "employerId" = $1"#)
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
        r#"INSERT INTO hiring_requests (id, "employerId", "jobType", status, "matchFeeInr") VALUES ($1, $2, $3, 'PENDING', 49)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("jobType").and_then(|v| v.as_str()).unwrap_or(""))
    .execute(&state.db)
    .await?;
    get_request(State(state), Path(id.to_string())).await
}

async fn get_request(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let row = sqlx::query(r#"SELECT * FROM hiring_requests WHERE id = $1"#)
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
    Path(id): Path<String>,
    Json(body): Json<ResolveBody>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE hiring_requests SET status = $1 WHERE id = $2"#)
        .bind(format!("RESOLVED_{}", body.choice))
        .bind(rid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "message": "Resolved" })))
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
    sqlx::query(r#"UPDATE hiring_interests SET status = $1 WHERE id = $2"#)
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
        "status": row.get::<String, _>("status"),
    })
}

fn request_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "status": row.get::<String, _>("status"),
        "matchFeeInr": row.get::<i32, _>("matchFeeInr"),
        "jobType": row.get::<Option<String>, _>("jobType"),
    })
}
