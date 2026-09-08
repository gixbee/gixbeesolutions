use std::time::Duration;

use rust_decimal::prelude::{FromPrimitive, ToPrimitive};
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;

pub const BATCH_SIZES: [i32; 3] = [40, 20, 10];
pub const BATCH_DELAYS_SECS: [u64; 3] = [0, 8 * 3600, 18 * 3600];
const GUARANTEE_WINDOW_SECS: u64 = 24 * 3600;

struct EmployerSalary {
    salary_min: f64,
    salary_max: f64,
    salary_negotiable: bool,
}

struct MatchedPreference {
    preference_id: Uuid,
    user_id: Uuid,
}

pub fn schedule_hiring_engine(state: AppState, request_id: String) {
    for (batch_index, delay_secs) in BATCH_DELAYS_SECS.iter().enumerate() {
        let state = state.clone();
        let request_id = request_id.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(*delay_secs)).await;
            if let Err(e) = send_batch(&state, &request_id, batch_index).await {
                warn!(
                    "hiring batch {} for {} failed: {}",
                    batch_index,
                    request_id,
                    e
                );
            }
        });
    }

    let state = state.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(GUARANTEE_WINDOW_SECS)).await;
        if let Err(e) = finalize_request(&state, &request_id).await {
            warn!("hiring finalize for {} failed: {}", request_id, e);
        }
    });
}

pub async fn send_batch(
    state: &AppState,
    request_id: &str,
    batch_index: usize,
) -> AppResult<()> {
    let rid = Uuid::parse_str(request_id)?;
    let request = sqlx::query(
        r#"SELECT status::text AS status, "employerId", "jobType", skills, location,
                  "salaryOffered", "salaryMin", "salaryMax", "salaryNegotiable",
                  "employmentType"::text AS "employmentType", "experienceMinYears",
                  "targetInterested", "batchesSent"
           FROM hiring_requests WHERE id = $1"#,
    )
    .bind(rid)
    .fetch_optional(&state.db)
    .await?;

    let request = match request {
        Some(r) => r,
        None => return Ok(()),
    };
    if request.get::<String, _>("status") != "COLLECTING" {
        return Ok(());
    }

    let interested = count_interested(state, rid).await?;
    let target = request.get::<i32, _>("targetInterested");
    if interested >= i64::from(target) {
        return Ok(());
    }

    let employer_id = request.get::<Uuid, _>("employerId");
    let already_notified: Vec<Uuid> = sqlx::query_scalar(
        r#"SELECT "candidateId" FROM hiring_interests WHERE "requestId" = $1"#,
    )
    .bind(rid)
    .fetch_all(&state.db)
    .await?;

    let batch_size = BATCH_SIZES
        .get(batch_index)
        .copied()
        .unwrap_or(BATCH_SIZES[BATCH_SIZES.len() - 1]);

    let salary = employer_salary_from_row(&request);
    let skills: Vec<String> = request
        .try_get::<Option<Vec<String>>, _>("skills")
        .ok()
        .flatten()
        .unwrap_or_default();
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
            request_id,
            batch_index
        );
        return Ok(());
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
        .execute(&state.db)
        .await?;
    }

    sqlx::query(
        r#"UPDATE hiring_requests SET "batchesSent" = COALESCE("batchesSent", 0) + 1 WHERE id = $1"#,
    )
    .bind(rid)
    .execute(&state.db)
    .await?;

    let salary_label = format_salary_label(&salary);
    let location_label = location.as_deref().unwrap_or("your area");
    let job_type = request.get::<String, _>("jobType");
    let body = format!(
        "{} · {} — tap Interested if you want this job.",
        salary_label,
        location_label
    );
    let candidate_ids: Vec<String> = matches.iter().map(|m| m.user_id.to_string()).collect();
    state
        .fcm
        .send_to_users(
            state,
            &candidate_ids,
            &format!("New {} opening", job_type),
            &body,
            Some(&[
                ("type", "hiring_offer"),
                ("requestId", request_id),
                ("jobType", &job_type),
            ]),
        )
        .await;

    info!(
        "[Hiring {}] batch {}: notified {} candidates",
        request_id,
        batch_index,
        matches.len()
    );
    Ok(())
}

pub async fn finalize_request(state: &AppState, request_id: &str) -> AppResult<()> {
    let rid = Uuid::parse_str(request_id)?;
    let request = sqlx::query(
        r#"SELECT status::text AS status, "employerId", "jobType", vacancies
           FROM hiring_requests WHERE id = $1"#,
    )
    .bind(rid)
    .fetch_optional(&state.db)
    .await?;

    let request = match request {
        Some(r) => r,
        None => return Ok(()),
    };
    if request.get::<String, _>("status") != "COLLECTING" {
        return Ok(());
    }

    let interested = count_interested(state, rid).await?;
    let vacancies = request.get::<i32, _>("vacancies").max(1);
    if interested >= i64::from(vacancies) {
        deliver_request(state, rid, interested).await?;
        return Ok(());
    }

    sqlx::query(r#"UPDATE hiring_requests SET status = 'GUARANTEE_FAILED' WHERE id = $1"#)
        .bind(rid)
        .execute(&state.db)
        .await?;

    let employer_id = request.get::<Uuid, _>("employerId").to_string();
    let job_type = request.get::<String, _>("jobType");
    state
        .fcm
        .send_to_user(
            state,
            &employer_id,
            "Hiring guarantee — action needed",
            &format!(
                "We couldn't collect the minimum interested candidates for {} within 24 hours. Choose instant Gixbee Credit or a refund in the app.",
                job_type
            ),
            Some(&[("type", "hiring_guarantee_failed"), ("requestId", request_id)]),
        )
        .await;

    info!(
        "[Hiring {}] guarantee FAILED ({}/{})",
        request_id,
        interested,
        vacancies
    );
    Ok(())
}

pub async fn deliver_request(
    state: &AppState,
    request_id: Uuid,
    interested_count: i64,
) -> AppResult<()> {
    let row = sqlx::query(
        r#"SELECT "employerId", "jobType", status::text AS status FROM hiring_requests WHERE id = $1"#,
    )
    .bind(request_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Hiring request not found".into()))?;

    if row.get::<String, _>("status") != "COLLECTING" {
        return Ok(());
    }

    sqlx::query(
        r#"UPDATE hiring_requests SET status = 'DELIVERED', "deliveredAt" = NOW() WHERE id = $1"#,
    )
    .bind(request_id)
    .execute(&state.db)
    .await?;

    let employer_id = row.get::<Uuid, _>("employerId").to_string();
    let job_type = row.get::<String, _>("jobType");
    let plural = if interested_count > 1 { "s" } else { "" };
    let rid_str = request_id.to_string();
    state
        .fcm
        .send_to_user(
            state,
            &employer_id,
            "Your candidate shortlist is ready! 🎉",
            &format!(
                "{} interested {} candidate{} — review and shortlist now.",
                interested_count,
                job_type,
                plural
            ),
            Some(&[("type", "hiring_delivered"), ("requestId", &rid_str)]),
        )
        .await;

    info!(
        "[Hiring {}] DELIVERED with {} interested",
        request_id,
        interested_count
    );
    Ok(())
}

pub async fn maybe_deliver_on_response(state: &AppState, request_id: Uuid) -> AppResult<()> {
    let row = sqlx::query(
        r#"SELECT status::text AS status, "targetInterested" FROM hiring_requests WHERE id = $1"#,
    )
    .bind(request_id)
    .fetch_optional(&state.db)
    .await?;

    let row = match row {
        Some(r) => r,
        None => return Ok(()),
    };
    if row.get::<String, _>("status") != "COLLECTING" {
        return Ok(());
    }

    let interested = count_interested(state, request_id).await?;
    if interested >= i64::from(row.get::<i32, _>("targetInterested")) {
        deliver_request(state, request_id, interested).await?;
    }
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

async fn find_matching_preferences(
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
    let mut query = String::from(
        r#"SELECT id, "userId", skills, "preferredLocation", "expectedSalary", "salaryNegotiable",
                  "employmentType"::text AS "employmentType", "experienceYears"
           FROM job_preferences
           WHERE "isActive" = true AND LOWER("jobType") = LOWER($1)
             AND "experienceYears" >= $2"#,
    );
    if location.map(|l| !l.trim().is_empty()).unwrap_or(false) {
        query.push_str(r#" AND LOWER("preferredLocation") LIKE $3"#);
    }
    query.push_str(r#" ORDER BY "createdAt" ASC LIMIT $4"#);

    let loc_pattern = location
        .map(|l| format!("%{}%", l.trim().to_lowercase()))
        .unwrap_or_default();

    let rows = if location.map(|l| !l.trim().is_empty()).unwrap_or(false) {
        sqlx::query(&query)
            .bind(job_type)
            .bind(experience_min)
            .bind(loc_pattern)
            .bind(limit.max(1) as i64)
            .fetch_all(&state.db)
            .await?
    } else {
        sqlx::query(
            r#"SELECT id, "userId", skills, "preferredLocation", "expectedSalary", "salaryNegotiable",
                      "employmentType"::text AS "employmentType", "experienceYears"
               FROM job_preferences
               WHERE "isActive" = true AND LOWER("jobType") = LOWER($1)
                 AND "experienceYears" >= $2
               ORDER BY "createdAt" ASC LIMIT $3"#,
        )
        .bind(job_type)
        .bind(experience_min)
        .bind(limit.max(1) as i64)
        .fetch_all(&state.db)
        .await?
    };

    let exclude: std::collections::HashSet<Uuid> = exclude_user_ids
        .iter()
        .chain(std::iter::once(&employer_id))
        .copied()
        .collect();

    let wanted: Vec<String> = skills
        .iter()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();

    let mut matches = Vec::new();
    for row in rows {
        let user_id = row.get::<Uuid, _>("userId");
        if exclude.contains(&user_id) {
            continue;
        }
        if !salary_range_matches(salary, &row) {
            continue;
        }
        if !employment_type_matches(
            employment_type,
            row.get::<Option<String>, _>("employmentType").as_deref(),
        ) {
            continue;
        }
        if !wanted.is_empty() {
            let have: Vec<String> = row
                .try_get::<Option<Vec<String>>, _>("skills")
                .ok()
                .flatten()
                .unwrap_or_default()
                .iter()
                .map(|s| s.to_lowercase())
                .collect();
            if !have.is_empty() && !have.iter().any(|s| wanted.contains(s)) {
                continue;
            }
        }
        matches.push(MatchedPreference {
            preference_id: row.get::<Uuid, _>("id"),
            user_id,
        });
        if matches.len() >= limit as usize {
            break;
        }
    }
    Ok(matches)
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

fn salary_range_matches(employer: &EmployerSalary, pref: &sqlx::postgres::PgRow) -> bool {
    let expected = pref
        .try_get::<Option<rust_decimal::Decimal>, _>("expectedSalary")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let effective_min = if employer.salary_negotiable {
        0.0
    } else {
        employer.salary_min
    };
    let pref_negotiable = pref.get::<bool, _>("salaryNegotiable");
    expected <= employer.salary_max && (pref_negotiable || expected >= effective_min)
}

fn normalize_employment(code: Option<&str>) -> Option<String> {
    match code.map(|s| s.trim().to_uppercase()) {
        Some(s) if s.is_empty() => None,
        Some(s) if s == "FULL_TIME" || s == "FULL-TIME" || s == "FULL TIME" => Some("FT".into()),
        Some(s) if s == "PART_TIME" || s == "PART-TIME" || s == "PART TIME" => Some("PT".into()),
        Some(s) => Some(s),
        None => None,
    }
}

fn employment_type_matches(employer: Option<&str>, seeker: Option<&str>) -> bool {
    let e = normalize_employment(employer);
    let s = normalize_employment(seeker);
    match (e, s) {
        (None, _) | (_, None) => true,
        (Some(a), Some(b)) => a == b,
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
    use crate::common::money::WALLET_PAYMENTS_ENABLED;
    use crate::common::pg::HIRING_REQUEST_COLS;
    use crate::payments::refund_hiring_match_payment;
    use crate::wallets::add_funds;

    let rid = Uuid::parse_str(request_id)?;
    let employer = Uuid::parse_str(employer_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "feeAmount", "creditApplied", "razorpayPaymentId"
           FROM hiring_requests WHERE id = $1 AND "employerId" = $2"#,
    )
    .bind(rid)
    .bind(employer)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Hiring request not found".into()))?;

    if row.get::<String, _>("status") != "GUARANTEE_FAILED" {
        return Err(AppError::BadRequest(
            "This request is not eligible for a guarantee remedy".into(),
        ));
    }

    let fee = row
        .try_get::<Option<rust_decimal::Decimal>, _>("feeAmount")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let credit_applied = row
        .try_get::<Option<rust_decimal::Decimal>, _>("creditApplied")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let razorpay_paid = ((fee - credit_applied).max(0.0) * 100.0).round() / 100.0;
    let razorpay_payment_id = row.get::<Option<String>, _>("razorpayPaymentId");

    let new_status = if choice == "REFUND" {
        if let Some(payment_id) = razorpay_payment_id.as_deref() {
            if razorpay_paid > 0.0 {
                refund_hiring_match_payment(state, payment_id, razorpay_paid.round() as i32)
                    .await?;
            }
        } else if WALLET_PAYMENTS_ENABLED && fee > 0.0 {
            add_funds(state, employer_id, fee.round() as i32, "Hiring guarantee refund").await?;
        }
        if !WALLET_PAYMENTS_ENABLED && credit_applied > 0.0 {
            add_hiring_credit(state, employer, credit_applied).await?;
        }
        "RESOLVED_REFUND"
    } else {
        if WALLET_PAYMENTS_ENABLED {
            add_funds(state, employer_id, fee.round() as i32, "Hiring guarantee credit").await?;
        } else {
            add_hiring_credit(state, employer, fee).await?;
        }
        "RESOLVED_CREDIT"
    };

    sqlx::query(
        r#"UPDATE hiring_requests SET status = $1, "resolvedAt" = NOW() WHERE id = $2"#,
    )
    .bind(new_status)
    .bind(rid)
    .execute(&state.db)
    .await?;

    sqlx::query(&format!(
        r#"SELECT {HIRING_REQUEST_COLS} FROM hiring_requests WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_one(&state.db)
    .await?
}

async fn add_hiring_credit(
    state: &AppState,
    employer_id: Uuid,
    amount_inr: f64,
) -> AppResult<()> {
    if amount_inr <= 0.0 {
        return Ok(());
    }
    let amount = rust_decimal::Decimal::from_f64_retain(amount_inr)
        .unwrap_or(rust_decimal::Decimal::ZERO);
    sqlx::query(
        r#"UPDATE users SET "hiringCreditBalance" = "hiringCreditBalance" + $1 WHERE id = $2"#,
    )
    .bind(amount)
    .bind(employer_id)
    .execute(&state.db)
    .await?;
    Ok(())
}
