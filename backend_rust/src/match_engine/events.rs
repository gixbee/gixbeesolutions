use uuid::Uuid;

use crate::error::AppResult;
use crate::state::AppState;

pub async fn record(
    state: &AppState,
    user_id: Option<Uuid>,
    job_id: Option<Uuid>,
    candidate_id: Option<Uuid>,
    business_id: Option<Uuid>,
    event_type: &str,
    score: Option<f32>,
) -> AppResult<()> {
    if let Err(err) = sqlx::query(
        r#"INSERT INTO matching_events
           (id, "userId", "jobPostId", "candidateId", "businessId", "eventType", "matchScoreAtTime")
           VALUES ($1,$2,$3,$4,$5,$6,$7)"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(job_id)
    .bind(candidate_id)
    .bind(business_id)
    .bind(event_type)
    .bind(score)
    .execute(&state.db)
    .await
    {
        tracing::warn!(%event_type, "matching event skipped: {err}");
    }
    Ok(())
}

pub async fn feedback(
    state: &AppState,
    user_id: Uuid,
    job_id: Uuid,
    candidate_id: Option<Uuid>,
    side: &str,
    reason: &str,
) -> AppResult<()> {
    sqlx::query(
        r#"INSERT INTO matching_feedback (id, "userId", "jobPostId", "candidateId", side, reason)
           VALUES ($1,$2,$3,$4,$5,$6)"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(job_id)
    .bind(candidate_id)
    .bind(side)
    .bind(reason)
    .execute(&state.db)
    .await?;
    Ok(())
}

pub fn pipeline_event(status: &str) -> Option<&'static str> {
    match status {
        "APPLIED" => Some("CANDIDATE_INTEREST"),
        "INTERVIEW" => Some("INTERVIEW_CREATED"),
        "SELECTED" => Some("HIRED"),
        "REJECTED" => Some("NOT_SELECTED"),
        "WITHDRAWN" => Some("WITHDRAWN"),
        _ => None,
    }
}

pub fn allowed_seeker_reason(reason: &str) -> bool {
    matches!(
        reason,
        "SALARY_TOO_LOW" | "TOO_FAR" | "WRONG_ROLE" | "WRONG_SCHEDULE" | "COMPANY" | "ALREADY_FOUND_WORK" | "OTHER"
    )
}

pub fn allowed_employer_reason(reason: &str) -> bool {
    matches!(
        reason,
        "MISSING_SKILL" | "EXPERIENCE" | "LOCATION" | "SALARY_EXPECTATION" | "AVAILABILITY" | "QUALIFICATION" |         "OTHER"
    )
}
