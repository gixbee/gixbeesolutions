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
        .route("/jobs/{id}", get(get_job).patch(close_job))
        .route("/jobs/{id}/apply", post(apply))
        .route("/jobs/{id}/applications", get(job_applications))
        .route("/applications/{id}/withdraw", post(withdraw))
        .route("/applications/{id}/status", patch(update_application_status))
}

async fn list_jobs(State(state): State<AppState>) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_POST_COLS} FROM job_posts WHERE "isActive" = true
        AND (job_posts."businessId" IS NULL OR EXISTS(
            SELECT 1 FROM businesses b
            WHERE b.id = job_posts."businessId" AND b.status::text = 'VERIFIED'))
        ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(post_json).collect()))
}

async fn matched_jobs(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let rows=sqlx::query(&format!(r#"SELECT {JOB_POST_COLS} FROM job_posts j WHERE "isActive"=true AND "employerId"<>$1
        AND (j."businessId" IS NULL OR EXISTS(
            SELECT 1 FROM businesses b
            WHERE b.id = j."businessId" AND b.status::text = 'VERIFIED'))
        ORDER BY EXISTS(SELECT 1 FROM job_preferences p WHERE p."userId"=$1 AND p."isActive"=true
          AND (NOT p."isPaid" OR p."paidUntil">NOW())
          AND (LOWER(j.title) LIKE '%'||LOWER(p."jobType")||'%' OR string_to_array(LOWER(j."requiredSkills"),',') && string_to_array(LOWER(p.skills),','))) DESC,
          j."createdAt" DESC LIMIT 100"#)).bind(Uuid::parse_str(&user.user_id)?).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(post_json).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct BusinessFilter {business_id:Option<Uuid>}
async fn my_jobs(State(state): State<AppState>, user: AuthUser,Query(filter):Query<BusinessFilter>) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {JOB_POST_COLS} FROM job_posts WHERE "employerId" = $1 AND ($2::uuid IS NULL OR "businessId"=$2) ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .bind(uid)
    .bind(filter.business_id)
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
    let business=crate::matching::resolve_business(&state,&user.user_id,&body).await?;
    let title=body.get("title").and_then(Value::as_str).unwrap_or("").trim();
    let description=body.get("description").and_then(Value::as_str).unwrap_or("").trim();
    if title.is_empty() || title.len()>200 || description.is_empty() || description.len()>10000 {
        return Err(AppError::BadRequest("Provide a job title and description".into()));
    }
    let salary_min=body.get("salaryMin").and_then(Value::as_f64);
    let salary_max=body.get("salaryMax").and_then(Value::as_f64);
    if [salary_min,salary_max].into_iter().flatten().any(|v|!v.is_finite()||v<0.0||v>99_999_999.0)
        || salary_min.zip(salary_max).is_some_and(|(min,max)|min>max) {
        return Err(AppError::BadRequest("Provide a valid monthly salary range".into()));
    }
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
        r#"INSERT INTO job_posts (id, "employerId", title, description, "requiredSkills", "jobType", experience, location, "salaryMin", "salaryMax", "isActive","businessId")
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true,$11)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(body.get("title").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(body.get("description").and_then(|v| v.as_str()).unwrap_or(""))
    .bind(skills.join(","))
    .bind(body.get("jobType").and_then(|v| v.as_str()))
    .bind(body.get("experience").and_then(|v| v.as_str()))
    .bind(body.get("location").and_then(|v| v.as_str()))
    .bind(body.get("salaryMin").and_then(|v| v.as_f64()))
    .bind(body.get("salaryMax").and_then(|v| v.as_f64()))
    .bind(business)
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
    let mut tx=state.db.begin().await?;
    let employer=sqlx::query_scalar::<_,Uuid>(r#"SELECT "employerId" FROM job_posts WHERE id=$1 AND "isActive"=true FOR UPDATE"#)
        .bind(pid).fetch_optional(&mut *tx).await?.ok_or_else(||AppError::NotFound("This job is no longer accepting applications".into()))?;
    if employer==uid {return Err(AppError::BadRequest("You cannot apply to your own job".into()));}
    let existing=sqlx::query(r#"SELECT id,status::text AS status FROM job_applications WHERE "jobPostId"=$1 AND "applicantId"=$2 ORDER BY "createdAt" DESC LIMIT 1"#)
        .bind(pid).bind(uid).fetch_optional(&mut *tx).await?;
    if let Some(existing)=existing {return Ok(Json(json!({"id":existing.get::<Uuid,_>("id"),"status":existing.get::<String,_>("status")})));}
    if body.get("coverLetter").and_then(Value::as_str).is_some_and(|s|s.len()>10000)
        || body.get("resumeUrl").and_then(Value::as_str).is_some_and(|s|s.len()>2000) {
        return Err(AppError::BadRequest("Application text or document reference is too long".into()));
    }
    sqlx::query(
        r#"INSERT INTO job_applications (id, "jobPostId", "applicantId", status, "coverLetter", "resumeUrl") VALUES ($1, $2, $3, 'APPLIED', $4, $5)"#,
    )
    .bind(app_id)
    .bind(pid)
    .bind(uid)
    .bind(body.get("coverLetter").and_then(|v| v.as_str()))
    .bind(body.get("resumeUrl").and_then(|v| v.as_str()))
    .execute(&mut *tx)
    .await?;
    crate::outbox::notify(&mut tx,pid,employer,"New job application","A candidate applied to your job post.",json!({"type":"board_application","jobId":pid,"audience":"employer"})).await?;
    tx.commit().await?;
    Ok(Json(json!({ "id": app_id.to_string(), "status": "APPLIED" })))
}

async fn my_applications(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT a.*,a.status::text AS status,to_jsonb(j) AS "jobPost" FROM job_applications a
            JOIN job_posts j ON j.id=a."jobPostId" WHERE a."applicantId"=$1 ORDER BY a."createdAt" DESC LIMIT 100"#
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
    user:AuthUser,
    Path(id): Path<String>,
    Query(_q): Query<PageQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let pid = Uuid::parse_str(&id)?;
    let owns:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM job_posts WHERE id=$1 AND "employerId"=$2)"#)
        .bind(pid).bind(Uuid::parse_str(&user.user_id)?).fetch_one(&state.db).await?;
    if !owns {return Err(AppError::NotFound("Job post not found on your account".into()));}
    let rows = sqlx::query(&format!(
        r#"SELECT a.*,a.status::text AS status,to_jsonb(j) AS "jobPost",jsonb_build_object('id',u.id,'fullName',u.name) AS applicant
            FROM job_applications a JOIN job_posts j ON j.id=a."jobPostId" JOIN users u ON u.id=a."applicantId"
            WHERE a."jobPostId"=$1 ORDER BY a."createdAt" DESC LIMIT 100"#
    ))
    .bind(pid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(app_json).collect()))
}

async fn withdraw(State(state): State<AppState>,user:AuthUser, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let aid = Uuid::parse_str(&id)?;
    let mut tx=state.db.begin().await?;
    let changed=sqlx::query_scalar::<_,Uuid>(r#"UPDATE job_applications SET status='WITHDRAWN',"updatedAt"=NOW()
        WHERE id=$1 AND "applicantId"=$2 AND status IN ('APPLIED','INTERVIEW','SELECTED') RETURNING "jobPostId""#)
        .bind(aid)
        .bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::Conflict("Your application cannot be withdrawn at this stage".into()))?;
    let employer:Uuid=sqlx::query_scalar(r#"SELECT "employerId" FROM job_posts WHERE id=$1"#).bind(changed).fetch_one(&mut *tx).await?;
    crate::outbox::notify(&mut tx,changed,employer,"Application withdrawn","A candidate withdrew their application.",json!({"type":"board_application","jobId":changed,"audience":"employer"})).await?;
    tx.commit().await?;
    Ok(Json(json!({ "status": "WITHDRAWN" })))
}

#[derive(Deserialize)]
struct StatusBody {
    status: String,
}

async fn update_application_status(
    State(state): State<AppState>,
    user:AuthUser,
    Path(id): Path<String>,
    Json(body): Json<StatusBody>,
) -> AppResult<Json<Value>> {
    let aid = Uuid::parse_str(&id)?;
    if !["INTERVIEW","SELECTED","REJECTED"].contains(&body.status.as_str()) {return Err(AppError::BadRequest("Unsupported application status".into()));}
    let mut tx=state.db.begin().await?;
    let changed=sqlx::query(r#"UPDATE job_applications a SET status=$1::job_applications_status_enum,"updatedAt"=NOW()
        FROM job_posts j WHERE a.id=$2 AND j.id=a."jobPostId" AND j."employerId"=$3
        AND (a.status::text=$1 OR (a.status='APPLIED' AND $1 IN ('INTERVIEW','REJECTED'))
            OR (a.status='INTERVIEW' AND $1 IN ('SELECTED','REJECTED')))
        RETURNING a."applicantId",a."jobPostId""#)
        .bind(&body.status)
        .bind(aid)
        .bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::Conflict("Application unavailable or transition not allowed".into()))?;
    crate::outbox::notify(&mut tx,changed.get("jobPostId"),changed.get("applicantId"),"Job application update",
        &format!("Your application is now {}.",body.status.to_lowercase()),json!({"type":"board_application","jobId":changed.get::<Uuid,_>("jobPostId"),"audience":"candidate"})).await?;
    tx.commit().await?;
    Ok(Json(json!({ "status": body.status })))
}

fn post_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "employerId": row.get::<Uuid, _>("employerId").to_string(),
        "title": row.get::<String, _>("title"),
        "description": row.get::<String, _>("description"),
        "businessId":row.get::<Option<Uuid>,_>("businessId"),
        "requiredSkills": crate::common::pg::string_list(row,"requiredSkills"),
        "jobType": row.get::<Option<String>, _>("jobType"),
        "experience": row.get::<Option<String>, _>("experience"),
        "location": row.get::<Option<String>, _>("location"),
        "salaryMin": row.try_get::<Option<rust_decimal::Decimal>, _>("salaryMin").ok().flatten(),
        "salaryMax": row.try_get::<Option<rust_decimal::Decimal>, _>("salaryMax").ok().flatten(),
        "isActive": row.get::<bool, _>("isActive"),
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "updatedAt": crate::common::pg::date_json(row,"updatedAt"),
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
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "jobPost":row.try_get::<Value,_>("jobPost").ok(),"applicant":row.try_get::<Value,_>("applicant").ok(),
    })
}

async fn close_job(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let result=sqlx::query(r#"UPDATE job_posts SET "isActive"=false,"updatedAt"=NOW() WHERE id=$1 AND "employerId"=$2"#)
        .bind(Uuid::parse_str(&id)?).bind(Uuid::parse_str(&user.user_id)?).execute(&state.db).await?;
    if result.rows_affected()==0 {return Err(AppError::NotFound("Job post not found on your account".into()));}
    Ok(Json(json!({"isActive":false})))
}
