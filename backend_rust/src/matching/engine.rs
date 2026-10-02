use std::time::Duration;

use rust_decimal::prelude::ToPrimitive;
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;

pub const BATCH_SIZES: [i32; 3] = [40, 20, 15];

#[derive(Clone)]
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
                  "targetInterested", "batchesSent", "deadlineAt" > NOW() AS open,
                  "positionId", "specializationIds", "skillIds", "qualificationId",
                  "qualificationRequired", "salaryPeriod", "locationId", "workMode", "languageIds"
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

    let position_id = request.try_get::<Option<String>, _>("positionId").ok().flatten();
    let specialization_ids = split_ids(request.try_get::<String, _>("specializationIds").unwrap_or_default());
    let skill_ids = split_ids(request.try_get::<String, _>("skillIds").unwrap_or_default());
    let qualification_id = request.try_get::<Option<String>, _>("qualificationId").ok().flatten();
    let qualification_required = request.try_get::<bool, _>("qualificationRequired").unwrap_or(false);
    let salary_period = request.try_get::<String, _>("salaryPeriod").unwrap_or_else(|_| "MONTHLY".into());
    let location_id = request.try_get::<Option<String>, _>("locationId").ok().flatten();
    let work_mode = request.try_get::<String, _>("workMode").unwrap_or_else(|_| "ONSITE".into());
    let language_ids = split_ids(request.try_get::<String, _>("languageIds").unwrap_or_default());
    let query = MatchQuery {
        position_id: position_id.as_deref(),
        job_type: &request.get::<String, _>("jobType"),
        specialization_ids: &specialization_ids,
        skill_ids: &skill_ids,
        qualification_id: qualification_id.as_deref(),
        qualification_required,
        salary_period: &salary_period,
        salary: &salary,
        employment_type: employment_type.as_deref(),
        location_id: location_id.as_deref(),
        location_text: location.as_deref(),
        experience_min,
        work_mode: &work_mode,
        language_ids: &language_ids,
    };
    let matches = find_matching_preferences(
        state,
        &query,
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
                format_salary_label(&salary, &salary_period),
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
    sqlx::query(
        r#"UPDATE hiring_requests SET status='DELIVERED'::hiring_requests_status_enum,
        "deliveredAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#,
    )
    .bind(request_id)
    .execute(&mut *tx)
    .await?;
    let title = "Your candidate shortlist is ready";
    let body = format!(
        "{} interested candidate{} for {} — review and shortlist in the app.",
        count,
        if count == 1 { "" } else { "s" },
        row.get::<String, _>("jobType")
    );
    crate::outbox::notify(
        &mut tx,
        request_id,
        row.get("employerId"),
        title,
        &body,
        serde_json::json!({"type":"hiring_delivered","requestId":request_id}),
    )
    .await?;
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

pub struct MatchQuery<'a> {
    pub position_id: Option<&'a str>,
    pub job_type: &'a str,
    pub specialization_ids: &'a [String],
    pub skill_ids: &'a [String],
    pub qualification_id: Option<&'a str>,
    pub qualification_required: bool,
    pub salary_period: &'a str,
    pub salary: &'a EmployerSalary,
    pub employment_type: Option<&'a str>,
    pub location_id: Option<&'a str>,
    pub location_text: Option<&'a str>,
    pub experience_min: i32,
    pub work_mode: &'a str,
    pub language_ids: &'a [String],
}

fn split_ids(value: String) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect()
}

pub(super) async fn find_matching_preferences(
    state: &AppState,
    query: &MatchQuery<'_>,
    employer_id: Uuid,
    exclude_user_ids: &[Uuid],
    limit: i32,
) -> AppResult<Vec<MatchedPreference>> {
    let excluded = exclude_user_ids
        .iter()
        .copied()
        .chain(std::iter::once(employer_id))
        .collect::<Vec<_>>();
    let salary_floor = if query.salary.salary_negotiable {
        0.0
    } else {
        query.salary.salary_min
    };
    let specialization_ids = query.specialization_ids.to_vec();
    let skill_ids = query.skill_ids.to_vec();
    let language_ids = query.language_ids.to_vec();
    let rows = sqlx::query(
        r#"SELECT id, "userId" FROM (
        SELECT DISTINCT ON (p."userId")
          p.id,
          p."userId",
          (
            SELECT COUNT(*) FROM unnest(string_to_array(COALESCE(p."skillIds",''), ',')) AS skill
            WHERE btrim(skill) <> '' AND btrim(skill) = ANY($14)
          ) AS skill_score,
          (
            SELECT COUNT(*) FROM unnest($17::text[]) AS want
            WHERE btrim(want) <> '' AND (
              btrim(want) = ANY(string_to_array(COALESCE(p."languageIds", ''), ','))
              OR btrim(want) = ANY(string_to_array(COALESCE(t."languageIds", ''), ','))
              OR EXISTS (
                SELECT 1 FROM hiring_languages hl
                WHERE hl.id = btrim(want) AND hl."isActive"
                  AND POSITION(LOWER(hl.label) IN LOWER(COALESCE(w.languages, ''))) > 0
              )
            )
          ) AS lang_score,
          CASE COALESCE(t.availability, 'IMMEDIATE')
            WHEN 'IMMEDIATE' THEN 0 WHEN 'DAYS_7' THEN 1 ELSE 2 END AS avail_rank,
          p."createdAt" AS pref_created
        FROM job_preferences p
        LEFT JOIN talent_profiles t ON t."userId" = p."userId"
        LEFT JOIN worker_profiles w ON w."userId" = p."userId"
        WHERE p."isActive" = true
          AND COALESCE(p."matchingPaused", false) = false
          AND p."experienceYears" >= $1 AND NOT (p."userId" = ANY($2))
          AND COALESCE(p."expectedSalaryPeriod", 'MONTHLY') = $3
          AND p."expectedSalary" <= $4 AND (p."salaryNegotiable" OR p."expectedSalary" >= $5)
          AND (NOT p."isPaid" OR p."paidUntil" IS NULL OR p."paidUntil" > NOW())
          AND (t.id IS NULL OR (t."profileStatus" <> 'PAUSED' AND t."jobAlertsEnabled" = true))
          AND ($6::text IS NULL OR p."employmentType" IS NULL OR p."employmentType"::text = $6
               OR (t."employmentTypes" IS NOT NULL AND POSITION($6 IN t."employmentTypes") > 0))
          AND (
            NULLIF(BTRIM(COALESCE(t."preferredWorkMode", '')), '') IS NULL
            OR UPPER(t."preferredWorkMode") = UPPER($16)
          )
          AND (
            ($7::text IS NOT NULL AND p."positionId" = $7)
            OR ($7::text IS NOT NULL AND EXISTS (
                   SELECT 1 FROM hiring_aliases a
                   WHERE a."isActive" AND a."entityType" = 'position' AND a."entityId" = $7
                     AND a.alias = p."positionId"
                 ))
            OR ($7::text IS NOT NULL AND p."positionId" IS NULL AND (
                 LOWER(p."jobType") = LOWER($8)
                 OR EXISTS (
                   SELECT 1 FROM hiring_aliases a
                   WHERE a."isActive" AND a."entityType" = 'position' AND a."entityId" = $7
                     AND LOWER(a.alias) = LOWER(p."jobType")
                 )
               ))
            OR ($7::text IS NULL AND LOWER(p."jobType") = LOWER($8))
          )
          AND (
            cardinality($9::text[]) = 0
            OR COALESCE(p."specializationIds", '') = ''
            OR EXISTS (
              SELECT 1
              FROM unnest(string_to_array(p."specializationIds", ',')) AS cand_spec
              CROSS JOIN unnest($9::text[]) AS req_spec
              WHERE btrim(cand_spec) <> '' AND btrim(req_spec) <> '' AND (
                btrim(cand_spec) = btrim(req_spec)
                OR EXISTS (
                  SELECT 1 FROM hiring_aliases sa
                  WHERE sa."entityType" = 'specialization' AND sa."isActive"
                    AND sa."entityId" = btrim(req_spec) AND sa.alias = btrim(cand_spec)
                )
              )
            )
          )
          AND (
            NOT $10
            OR $11::text IS NULL
            OR p."qualificationId" = $11
            OR t."qualificationId" = $11
            OR (
              (SELECT rank FROM hiring_qualifications WHERE id = COALESCE(p."qualificationId", t."qualificationId"))
              >= (SELECT rank FROM hiring_qualifications WHERE id = $11)
              AND (SELECT rank FROM hiring_qualifications WHERE id = $11) IS NOT NULL
              AND (SELECT rank FROM hiring_qualifications WHERE id = COALESCE(p."qualificationId", t."qualificationId")) IS NOT NULL
            )
          )
          AND (
            $16 = 'REMOTE'
            OR (
              $12::text IS NOT NULL AND (
                p."locationId" = $12 OR t."locationId" = $12
                OR EXISTS (
                  SELECT 1 FROM hiring_locations req
                  JOIN hiring_locations cand ON cand.id = COALESCE(p."locationId", t."locationId")
                  WHERE req.id = $12 AND req."districtId" IS NOT NULL AND req."districtId" = cand."districtId"
                )
                OR EXISTS (
                  SELECT 1 FROM hiring_locations req
                  JOIN hiring_locations cand ON cand.id = COALESCE(p."locationId", t."locationId")
                  WHERE req.id = $12 AND req.lat IS NOT NULL AND req.lng IS NOT NULL
                    AND cand.lat IS NOT NULL AND cand.lng IS NOT NULL
                    AND ST_DWithin(
                      ST_SetSRID(ST_MakePoint(req.lng, req.lat), 4326)::geography,
                      ST_SetSRID(ST_MakePoint(cand.lng, cand.lat), 4326)::geography,
                      COALESCE(t."travelRadiusKm", 25) * 1000
                    )
                )
                OR (
                  COALESCE(NULLIF(p."locationId", ''), NULLIF(t."locationId", '')) IS NULL
                  AND t.lat IS NOT NULL AND t.lng IS NOT NULL
                  AND EXISTS (
                    SELECT 1 FROM hiring_locations req
                    WHERE req.id = $12 AND req.lat IS NOT NULL AND req.lng IS NOT NULL
                      AND ST_DWithin(
                        ST_SetSRID(ST_MakePoint(req.lng, req.lat), 4326)::geography,
                        ST_SetSRID(ST_MakePoint(t.lng, t.lat), 4326)::geography,
                        COALESCE(t."travelRadiusKm", 25) * 1000
                      )
                  )
                )
              )
            )
            OR (
              $12::text IS NULL AND (
                $13 = ''
                OR POSITION($13 IN LOWER(COALESCE(p."preferredLocation",''))) > 0
                OR POSITION($13 IN LOWER(COALESCE(t."addressText",''))) > 0
              )
            )
          )
        ORDER BY p."userId",
          skill_score DESC,
          lang_score DESC,
          avail_rank ASC,
          pref_created ASC,
          p.id ASC
        ) best
        ORDER BY skill_score DESC, lang_score DESC, avail_rank ASC, pref_created ASC, id ASC
        LIMIT $15"#,
    )
    .bind(query.experience_min.max(0))
    .bind(excluded)
    .bind(query.salary_period)
    .bind(rust_decimal::Decimal::from_f64_retain(query.salary.salary_max).unwrap_or_default())
    .bind(rust_decimal::Decimal::from_f64_retain(salary_floor).unwrap_or_default())
    .bind(query.employment_type)
    .bind(query.position_id)
    .bind(query.job_type.trim())
    .bind(&specialization_ids)
    .bind(query.qualification_required)
    .bind(query.qualification_id)
    .bind(query.location_id)
    .bind(query.location_text.unwrap_or("").trim().to_lowercase())
    .bind(&skill_ids)
    .bind(i64::from(limit.max(1)))
    .bind(query.work_mode)
    .bind(&language_ids)
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

fn format_salary_label(salary: &EmployerSalary, salary_period: &str) -> String {
    let suffix = match salary_period.trim().to_ascii_uppercase().as_str() {
        "HOURLY" => "/hour",
        "DAILY" => "/day",
        "WEEKLY" => "/week",
        "PER_JOB" => "/job",
        _ => "/month",
    };
    if salary.salary_min > 0.0 && salary.salary_min <= salary.salary_max {
        format!(
            "₹{}–₹{}{suffix}",
            salary.salary_min.round(),
            salary.salary_max.round()
        )
    } else {
        format!("₹{}{suffix}", salary.salary_max.round())
    }
}

