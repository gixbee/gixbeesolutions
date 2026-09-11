use std::time::Duration;

use rust_decimal::prelude::ToPrimitive;
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;

pub const BATCH_SIZES: [i32; 3] = [40, 20, 10];

pub(super) struct EmployerSalary {
    pub salary_min: f64,
    pub salary_max: f64,
    pub salary_negotiable: bool,
}

pub(super) struct MatchedPreference {
    preference_id: Uuid,
    user_id: Uuid,
}

pub fn schedule_hiring_engine(state: AppState, request_id: String) {
    // Immediate wake-up is only an optimization. The database poller recovers every pending batch.
    tokio::spawn(async move {
        if let Err(e) = send_batch(&state, &request_id, 0).await {
            warn!("hiring initial batch: {}", e);
        }
    });
}

pub async fn run_scheduler(state: AppState) {
    let mut tick = tokio::time::interval(Duration::from_secs(30));
    loop {
        tick.tick().await;
        if let Err(e) = poll_due(&state).await {
            warn!("hiring scheduler: {}", e);
        }
    }
}

pub(super) async fn poll_due(state: &AppState) -> AppResult<()> {
    let rows = sqlx::query(
        r#"SELECT id,"batchesSent","deadlineAt"<=NOW() AS expired
        FROM hiring_requests WHERE status='COLLECTING' AND (
        "deadlineAt"<=NOW() OR "batchesSent"=0
        OR "batchesSent"=1 AND "deadlineAt"-INTERVAL '16 hours'<=NOW()
        OR "batchesSent"=2 AND "deadlineAt"-INTERVAL '6 hours'<=NOW())
        ORDER BY "deadlineAt" ASC LIMIT 100"#,
    )
    .fetch_all(&state.db)
    .await?;
    for row in rows {
        let id = row.get::<Uuid, _>("id").to_string();
        let result = if row.get::<bool, _>("expired") {
            finalize_request(state, &id).await
        } else {
            send_batch(state, &id, row.get::<i32, _>("batchesSent") as usize).await
        };
        if let Err(e) = result {
            warn!("hiring request {}: {}", id, e);
        }
    }
    Ok(())
}

pub async fn send_batch(state: &AppState, request_id: &str, batch_index: usize) -> AppResult<()> {
    let rid = Uuid::parse_str(request_id)?;
    let mut tx = state.db.begin().await?;
    let request = sqlx::query(
        r#"SELECT status::text AS status, "employerId", "jobType", skills, location,
                  "salaryOffered", "salaryMin", "salaryMax", "salaryNegotiable",
                  "employmentType"::text AS "employmentType", "experienceMinYears",
                  "targetInterested", "batchesSent", "deadlineAt" > NOW() AS open
           FROM hiring_requests WHERE id = $1 FOR UPDATE SKIP LOCKED"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?;

    let request = match request {
        Some(r) => r,
        None => return Ok(()),
    };
    if request.get::<String, _>("status") != "COLLECTING"
        || !request.get::<bool, _>("open")
        || request.get::<i32, _>("batchesSent") != batch_index as i32
        || batch_index >= BATCH_SIZES.len()
    {
        return Ok(());
    }

    let interested = count_interested(state, rid).await?;
    let target = request.get::<i32, _>("targetInterested");
    if interested >= i64::from(target) {
        return Ok(());
    }

    let employer_id = request.get::<Uuid, _>("employerId");
    let already_notified: Vec<Uuid> =
        sqlx::query_scalar(r#"SELECT "candidateId" FROM hiring_interests WHERE "requestId" = $1"#)
            .bind(rid)
            .fetch_all(&state.db)
            .await?;

    let batch_size = BATCH_SIZES
        .get(batch_index)
        .copied()
        .unwrap_or(BATCH_SIZES[BATCH_SIZES.len() - 1]);

    let salary = employer_salary_from_row(&request);
    let skills = crate::common::pg::string_list(&request, "skills");
    let employment_type = request.get::<Option<String>, _>("employmentType");
    let experience_min = request.get::<i32, _>("experienceMinYears");
    let location = request.get::<Option<String>, _>("location");

    let matches = find_matching_preferences(
        state,
        &request.get::<String, _>("jobType"),
        &salary,
        employment_type.as_deref(),
        location.as_deref(),
        experience_min,
        &skills,
        employer_id,
        &already_notified,
        batch_size,
    )
    .await?;

    if matches.is_empty() {
        info!(
            "[Hiring {}] batch {}: no fresh matches",
            request_id, batch_index
        );
    }

    for m in &matches {
        sqlx::query(
            r#"INSERT INTO hiring_interests (id, "requestId", "candidateId", "preferenceId", response, "notifiedAt")
               VALUES ($1, $2, $3, $4, 'PENDING', NOW())
               ON CONFLICT ("requestId", "candidateId") DO NOTHING"#,
        )
        .bind(Uuid::new_v4())
        .bind(rid)
        .bind(m.user_id)
        .bind(m.preference_id)
        .execute(&mut *tx)
        .await?;
        crate::outbox::notify(
            &mut tx,
            rid,
            m.user_id,
            &format!("New {} opening", request.get::<String, _>("jobType")),
            &format!(
                "{} · {} — tap Interested if you want this job.",
                format_salary_label(&salary),
                location.as_deref().unwrap_or("your area")
            ),
            serde_json::json!({"type":"hiring_offer","requestId":request_id}),
        )
        .await?;
    }

    sqlx::query(
        r#"UPDATE hiring_requests SET "batchesSent" = COALESCE("batchesSent", 0) + 1 WHERE id = $1"#,
    )
    .bind(rid)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    info!(
        "[Hiring {}] batch {}: notified {} candidates",
        request_id,
        batch_index,
        matches.len()
    );
    Ok(())
}

pub async fn finalize_request(state: &AppState, request_id: &str) -> AppResult<()> {
    finish_request(state, Uuid::parse_str(request_id)?, true).await
}

pub async fn maybe_deliver_on_response(state: &AppState, request_id: Uuid) -> AppResult<()> {
    finish_request(state, request_id, false).await
}

async fn finish_request(state: &AppState, request_id: Uuid, at_deadline: bool) -> AppResult<()> {
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        r#"SELECT "employerId","jobType",status::text AS status,vacancies,"targetInterested",
        "deadlineAt"<=NOW() AS expired FROM hiring_requests WHERE id=$1 FOR UPDATE"#,
    )
    .bind(request_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(row) = row else {
        return Ok(());
    };
    if row.get::<String, _>("status") != "COLLECTING" {
        return Ok(());
    }
    let expired = row.get::<bool, _>("expired");
    if at_deadline && !expired {
        return Ok(());
    }
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM hiring_interests WHERE "requestId"=$1 AND response='INTERESTED'"#,
    )
    .bind(request_id)
    .fetch_one(&mut *tx)
    .await?;
    if !expired && count < i64::from(row.get::<i32, _>("targetInterested")) {
        return Ok(());
    }
    let delivered = count >= i64::from(row.get::<i32, _>("vacancies"));
    let status = if delivered {
        "DELIVERED"
    } else {
        "GUARANTEE_FAILED"
    };
    sqlx::query(r#"UPDATE hiring_requests SET status=$1::hiring_requests_status_enum,
        "deliveredAt"=CASE WHEN $2 THEN NOW() ELSE "deliveredAt" END,"updatedAt"=NOW() WHERE id=$3"#)
        .bind(status).bind(delivered).bind(request_id).execute(&mut *tx).await?;
    let (title, body) = if delivered {
        (
            "Your candidate shortlist is ready",
            format!(
                "{} interested candidates for {} — review and shortlist in the app.",
                count,
                row.get::<String, _>("jobType")
            ),
        )
    } else {
        ("Hiring guarantee — action needed","The minimum interested candidates were not collected within 24 hours. Choose hiring credit or a refund in the app.".into())
    };
    crate::outbox::notify(&mut tx,request_id,row.get("employerId"),title,&body,
        serde_json::json!({"type":if delivered {"hiring_delivered"} else {"hiring_guarantee_failed"},"requestId":request_id})).await?;
    tx.commit().await?;
    Ok(())
}

async fn count_interested(state: &AppState, request_id: Uuid) -> AppResult<i64> {
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*)::bigint FROM hiring_interests
           WHERE "requestId" = $1 AND response::text = 'INTERESTED'"#,
    )
    .bind(request_id)
    .fetch_one(&state.db)
    .await?;
    Ok(count)
}

pub(super) async fn find_matching_preferences(
    state: &AppState,
    job_type: &str,
    salary: &EmployerSalary,
    employment_type: Option<&str>,
    location: Option<&str>,
    experience_min: i32,
    skills: &[String],
    employer_id: Uuid,
    exclude_user_ids: &[Uuid],
    limit: i32,
) -> AppResult<Vec<MatchedPreference>> {
    let excluded = exclude_user_ids
        .iter()
        .copied()
        .chain(std::iter::once(employer_id))
        .collect::<Vec<_>>();
    let wanted = skills
        .iter()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>();
    // Apply all criteria before LIMIT: early non-matches must not hide later candidates.
    // Nest stores simple-array skills as comma-separated text.
    let rows = sqlx::query(
        r#"SELECT id, "userId" FROM job_preferences
        WHERE "isActive" = true AND LOWER("jobType") = LOWER($1)
          AND "experienceYears" >= $2 AND NOT ("userId" = ANY($3))
          AND ($4 = '' OR POSITION($4 IN LOWER(COALESCE("preferredLocation",''))) > 0)
          AND "expectedSalary" <= $5 AND ("salaryNegotiable" OR "expectedSalary" >= $6)
          AND ($7::text IS NULL OR "employmentType" IS NULL OR "employmentType"::text = $7)
          AND (cardinality($8::text[]) = 0 OR COALESCE(skills,'') = '' OR EXISTS (
              SELECT 1 FROM unnest(string_to_array(LOWER(skills),',')) AS skill
              WHERE btrim(skill) = ANY($8)))
        ORDER BY "createdAt" ASC, id ASC LIMIT $9"#,
    )
    .bind(job_type.trim())
    .bind(experience_min.max(0))
    .bind(excluded)
    .bind(location.unwrap_or("").trim().to_lowercase())
    .bind(rust_decimal::Decimal::from_f64_retain(salary.salary_max).unwrap_or_default())
    .bind(
        rust_decimal::Decimal::from_f64_retain(if salary.salary_negotiable {
            0.0
        } else {
            salary.salary_min
        })
        .unwrap_or_default(),
    )
    .bind(employment_type)
    .bind(wanted)
    .bind(i64::from(limit.max(1)))
    .fetch_all(&state.db)
    .await?;
    Ok(rows
        .iter()
        .map(|row| MatchedPreference {
            preference_id: row.get("id"),
            user_id: row.get("userId"),
        })
        .collect())
}

fn employer_salary_from_row(row: &sqlx::postgres::PgRow) -> EmployerSalary {
    let salary_max = row
        .try_get::<Option<rust_decimal::Decimal>, _>("salaryMax")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let salary_offered = row
        .try_get::<Option<rust_decimal::Decimal>, _>("salaryOffered")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let salary_min = row
        .try_get::<Option<rust_decimal::Decimal>, _>("salaryMin")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let max = if salary_max > 0.0 {
        salary_max
    } else {
        salary_offered
    };
    EmployerSalary {
        salary_min,
        salary_max: max,
        salary_negotiable: row.get::<bool, _>("salaryNegotiable"),
    }
}

fn format_salary_label(salary: &EmployerSalary) -> String {
    if salary.salary_min > 0.0 && salary.salary_min < salary.salary_max {
        format!(
            "₹{}–₹{}/month",
            salary.salary_min.round(),
            salary.salary_max.round()
        )
    } else {
        format!("₹{}/month", salary.salary_max.round())
    }
}

pub async fn resolve_guarantee(
    state: &AppState,
    employer_id: &str,
    request_id: &str,
    choice: &str,
) -> AppResult<sqlx::postgres::PgRow> {
    use crate::common::pg::HIRING_REQUEST_COLS;
    if !matches!(choice, "CREDIT" | "REFUND") {
        return Err(AppError::BadRequest("Choose CREDIT or REFUND".into()));
    }
    let rid = Uuid::parse_str(request_id)?;
    let employer = Uuid::parse_str(employer_id)?;
    let mut tx = state.db.begin().await?;
    let row=sqlx::query(&format!(r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE id=$1 AND "employerId"=$2 FOR UPDATE"#))
        .bind(rid).bind(employer).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::NotFound("Hiring request not found".into()))?;
    let status = row.get::<String, _>("status");
    if status == format!("RESOLVED_{choice}") {
        return Ok(row);
    }
    if status != "GUARANTEE_FAILED" {
        return Err(AppError::BadRequest(
            "This request is not eligible for a guarantee remedy".into(),
        ));
    }
    let pending:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM outbox_events WHERE "aggregateId"=$1 AND type='hiring.refund')"#)
        .bind(rid).fetch_one(&mut *tx).await?;
    if pending {
        if choice == "REFUND" {
            return Ok(row);
        }
        return Err(AppError::Conflict(
            "A refund has already been requested".into(),
        ));
    }
    if choice == "CREDIT" {
        sqlx::query(
            r#"UPDATE users SET "hiringCreditBalance"="hiringCreditBalance"+$1 WHERE id=$2"#,
        )
        .bind(row.get::<rust_decimal::Decimal, _>("feeAmount"))
        .bind(employer)
        .execute(&mut *tx)
        .await?;
        sqlx::query(r#"UPDATE hiring_requests SET status='RESOLVED_CREDIT',"resolvedAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#)
            .bind(rid).execute(&mut *tx).await?;
    } else {
        // Persist the immutable remedy before calling Razorpay. A timeout must never
        // let a later CREDIT request grant a second remedy for the same fee.
        sqlx::query(r#"INSERT INTO outbox_events (id,type,"aggregateId",payload) VALUES ($1,'hiring.refund',$2,$3)"#)
            .bind(Uuid::new_v4()).bind(rid).bind(serde_json::json!({"requestId":rid})).execute(&mut *tx).await?;
    }
    let result = sqlx::query(&format!(
        "SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE id=$1"
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(result)
}

pub async fn process_refund(state: &AppState, request_id: &str) -> AppResult<()> {
    let rid = Uuid::parse_str(request_id)?;
    let mut tx = state.db.begin().await?;
    let row=sqlx::query(r#"SELECT status::text AS status,"employerId","feeAmount","creditApplied","razorpayPaymentId"
        FROM hiring_requests WHERE id=$1 FOR UPDATE"#).bind(rid).fetch_one(&mut *tx).await?;
    if row.get::<String, _>("status") == "RESOLVED_REFUND" {
        return Ok(());
    }
    if row.get::<String, _>("status") != "GUARANTEE_FAILED" {
        return Err(AppError::Conflict(
            "Refund request has an unexpected status".into(),
        ));
    }
    let fee = row.get::<rust_decimal::Decimal, _>("feeAmount");
    let credit = row.get::<rust_decimal::Decimal, _>("creditApplied");
    let cash = fee - credit;
    if cash > rust_decimal::Decimal::ZERO {
        let payment_id = row
            .get::<Option<String>, _>("razorpayPaymentId")
            .ok_or_else(|| AppError::Conflict("Captured payment reference is missing".into()))?;
        crate::payments::refund_hiring_match_payment(
            state,
            &payment_id,
            cash.to_i32()
                .ok_or_else(|| AppError::Internal("Invalid refund amount".into()))?,
            request_id,
        )
        .await?;
    }
    sqlx::query(r#"UPDATE users SET "hiringCreditBalance"="hiringCreditBalance"+$1 WHERE id=$2"#)
        .bind(credit)
        .bind(row.get::<Uuid, _>("employerId"))
        .execute(&mut *tx)
        .await?;
    sqlx::query(r#"UPDATE hiring_requests SET status='RESOLVED_REFUND',"resolvedAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#)
        .bind(rid).execute(&mut *tx).await?;
    crate::outbox::notify(
        &mut tx,
        rid,
        row.get("employerId"),
        "Hiring refund initiated",
        "Your hiring fee refund was accepted. Any hiring credit used has been restored.",
        serde_json::json!({"type":"hiring_refund","requestId":rid}),
    )
    .await?;
    tx.commit().await?;
    Ok(())
}
