use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::{JOB_APPLICATION_COLS, JOB_POST_COLS};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/jobs", get(list_jobs).post(create_job))
        .route("/jobs/matched", get(matched_jobs))
        .route("/my-jobs", get(my_jobs))
        .route("/my-applications", get(my_applications))
        .route("/jobs/{id}", get(get_job))
        .route("/jobs/{id}/apply", post(apply))
        .route("/jobs/{id}/applications", get(job_applications))
        .route("/applications/{id}/withdraw", post(withdraw))
        .route("/applications/{id}/status", patch(update_application_status))
}

async fn list_jobs(State(state): State<AppState>) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_POST_COLS} FROM job_posts WHERE "isActive" = true ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(post_json).collect()))
}

async fn matched_jobs(State(state): State<AppState>, _user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    list_jobs(State(state)).await
}

async fn my_jobs(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_POST_COLS} FROM job_posts WHERE "employerId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(post_json).collect()))
}

async fn create_job(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let skills: Vec<String> = body
        .get("requiredSkills")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|s| s.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();
    sqlx::query(
        r#"INSERT INTO job_posts (id, "employerId", title, description, "requiredSkills", "jobType", experience, location, "salaryMin", "salaryMax", "isActive")
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("title").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(body.get("description").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(&skills)
    .bind(body.get("jobType").and_then(|v| v.as_str()))
    .bind(body.get("experience").and_then(|v| v.as_str()))
    .bind(body.get("location").and_then(|v| v.as_str()))
    .bind(body.get("salaryMin").and_then(|v| v.as_f64()))
    .bind(body.get("salaryMax").and_then(|v| v.as_f64()))
    .execute(&state.db)
    .await?;
    get_job(State(state), Path(id.to_string())).await
}

async fn get_job(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let pid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {JOB_POST_COLS} FROM job_posts WHERE id = $1"#
    ))
    .bind(pid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Job post not found".into()))?;
    Ok(Json(post_json(&row)))
}

async fn apply(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let pid = Uuid::parse_str(&id)?;
    let app_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO job_applications (id, "jobPostId", "applicantId", status, "coverLetter", "resumeUrl") VALUES ($1, $2, $3, 'APPLIED', $4, $5)"#,
    )
    .bind(app_id)
    .bind(pid)
    .bind(uid)
    .bind(body.get("coverLetter").and_then(|v| v.as_str()))
    .bind(body.get("resumeUrl").and_then(|v| v.as_str()))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "id": app_id.to_string(), "status": "APPLIED" })))
}

async fn my_applications(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_APPLICATION_COLS} FROM job_applications WHERE "applicantId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(app_json).collect()))
}

#[derive(Deserialize)]
struct PageQuery {
    page: Option<String>,
    limit: Option<String>,
}

async fn job_applications(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Query(_q): Query<PageQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let pid = Uuid::parse_str(&id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_APPLICATION_COLS} FROM job_applications WHERE "jobPostId" = $1 ORDER BY "createdAt" DESC LIMIT 50"#
    ))
    .bind(pid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(app_json).collect()))
}

async fn withdraw(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let aid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE job_applications SET status = 'WITHDRAWN' WHERE id = $1"#)
        .bind(aid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "status": "WITHDRAWN" })))
}

#[derive(Deserialize)]
struct StatusBody {
    status: String,
}

async fn update_application_status(
    State(state): State<AppState>,
    Path(id): Path<String>,
    Json(body): Json<StatusBody>,
) -> AppResult<Json<Value>> {
    let aid = Uuid::parse_str(&id)?;
    sqlx::query(r#"UPDATE job_applications SET status = $1 WHERE id = $2"#)
        .bind(&body.status)
        .bind(aid)
        .execute(&state.db)
        .await?;
    Ok(Json(json!({ "status": body.status })))
}

fn post_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "employerId": row.get::<Uuid, _>("employerId").to_string(),
        "title": row.get::<String, _>("title"),
        "description": row.get::<String, _>("description"),
        "requiredSkills": row.try_get::<Option<Vec<String>>, _>("requiredSkills").ok().flatten(),
        "jobType": row.get::<Option<String>, _>("jobType"),
        "experience": row.get::<Option<String>, _>("experience"),
        "location": row.get::<Option<String>, _>("location"),
        "salaryMin": row.try_get::<Option<rust_decimal::Decimal>, _>("salaryMin").ok().flatten(),
        "salaryMax": row.try_get::<Option<rust_decimal::Decimal>, _>("salaryMax").ok().flatten(),
        "isActive": row.get::<bool, _>("isActive"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
        "updatedAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("updatedAt").ok(),
    })
}

fn app_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "jobPostId": row.get::<Uuid, _>("jobPostId").to_string(),
        "applicantId": row.get::<Uuid, _>("applicantId").to_string(),
        "status": row.get::<String, _>("status"),
        "coverLetter": row.get::<Option<String>, _>("coverLetter"),
        "resumeUrl": row.get::<Option<String>, _>("resumeUrl"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
    })
}
