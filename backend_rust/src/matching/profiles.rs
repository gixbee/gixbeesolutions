use rust_decimal::prelude::FromPrimitive;
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    common::pg::JOB_PREFERENCE_COLS,
    error::{AppError, AppResult},
    state::AppState,
};

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Preference {
    pub job_type: String,
    #[serde(default)]
    pub skills: Vec<String>,
    pub preferred_location: Option<String>,
    #[serde(default)]
    pub expected_salary: f64,
    #[serde(default)]
    pub salary_negotiable: bool,
    pub employment_type: Option<String>,
    #[serde(default)]
    pub experience_years: i32,
    pub notice_period: Option<String>,
}

pub(super) fn employment_type(value: Option<&str>) -> AppResult<Option<String>> {
    let Some(value) = value.filter(|v| !v.trim().is_empty()) else {
        return Ok(None);
    };
    let normalized = match value.trim().to_uppercase().as_str() {
        "FT" | "FULL_TIME" | "FULL TIME" | "FULL-TIME" => "FT",
        "PT" | "PART_TIME" | "PART TIME" | "PART-TIME" => "PT",
        "INTERN" | "INTERNSHIP" => "INTERN",
        "CONTRACT" => "CONTRACT",
        _ => return Err(AppError::BadRequest("Unsupported employment type".into())),
    };
    Ok(Some(normalized.into()))
}

impl Preference {
    pub fn parse(body: &Value) -> AppResult<Self> {
        let mut input: Self = serde_json::from_value(body.clone())
            .map_err(|_| AppError::BadRequest("Invalid career profile fields".into()))?;
        input.job_type = input.job_type.trim().to_string();
        if input.job_type.is_empty()
            || input.job_type.len() > 150
            || !input.expected_salary.is_finite()
            || !(0.0..=99_999_999.0).contains(&input.expected_salary)
            || !(0..=80).contains(&input.experience_years)
        {
            return Err(AppError::BadRequest(
                "Provide a job type, non-negative salary and valid experience".into(),
            ));
        }
        if input.skills.len() > 50
            || input
                .skills
                .iter()
                .any(|s| s.contains(',') || s.len() > 100)
        {
            return Err(AppError::BadRequest(
                "Provide at most 50 individual skills without commas".into(),
            ));
        }
        input.skills = input
            .skills
            .iter()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        input.employment_type = employment_type(input.employment_type.as_deref())?;
        let notice = input
            .notice_period
            .get_or_insert_with(|| "IMMEDIATE".into());
        if !["IMMEDIATE", "DAYS_15", "DAYS_30", "DAYS_60", "DAYS_90"].contains(&notice.as_str()) {
            return Err(AppError::BadRequest("Unsupported notice period".into()));
        }
        Ok(input)
    }

    pub fn salary(&self) -> Decimal {
        Decimal::from_f64(self.expected_salary)
            .unwrap_or_default()
            .round_dp(2)
    }
}

pub(super) async fn create(
    state: &AppState,
    user_id: &str,
    body: &Value,
    paid: bool,
    payment_id:Option<Uuid>,
) -> AppResult<Value> {
    let input = Preference::parse(body)?;
    let uid = Uuid::parse_str(user_id)?;
    let mut tx = state.db.begin().await?;
    // All profile creation, including captured-payment fulfillment, serializes
    // through the owner so concurrent requests cannot consume the free slots twice.
    sqlx::query("SELECT id FROM users WHERE id = $1 FOR UPDATE")
        .bind(uid)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("Account not found".into()))?;
    if let Some(payment_id)=payment_id {
        let fulfilled:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM career_profile_receipts WHERE "paymentOrderId"=$1)"#)
            .bind(payment_id).fetch_one(&mut *tx).await?;
        if fulfilled {return Ok(json!({"fulfilled":true}));}
    } else {
        let pending:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM payment_orders WHERE "userId"=$1 AND status='CREATED'
            AND purpose='EXTRA_JOB_TYPE_FEE' AND LOWER(meta->>'jobType')=LOWER($2))"#)
            .bind(uid).bind(&input.job_type).fetch_one(&mut *tx).await?;
        if pending {return Err(AppError::Conflict("This profile has a pending payment. Resume it from Pending payments".into()));}
    }
    let existing = sqlx::query(&format!(r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE "userId" = $1 AND "isActive" = true"#))
        .bind(uid).fetch_all(&mut *tx).await?;
    if let Some(found) = existing.iter().find(|r| {
        r.get::<String, _>("jobType")
            .eq_ignore_ascii_case(&input.job_type)
    }) {
        if paid {
            let id=found.get::<Uuid,_>("id");
            if !found.get::<bool,_>("isPaid") {return Err(AppError::Conflict("This profile already has a free entitlement. Contact support about the paid order".into()));}
            sqlx::query(r#"UPDATE job_preferences SET "paidUntil"=GREATEST(COALESCE("paidUntil",NOW()),NOW())+INTERVAL '30 days',"updatedAt"=NOW() WHERE id=$1"#)
                .bind(id).execute(&mut *tx).await?;
            if let Some(payment_id)=payment_id {record_receipt(&mut tx,payment_id,id).await?;}
            tx.commit().await?;
            return Ok(json!({"id":id,"renewed":true}));
        }
        return Err(AppError::Conflict(
            "You already have a profile for this job type".into(),
        ));
    }
    if !paid && existing.len() >= 2 {
        return Ok(json!({"needsPayment": true, "fee": 50}));
    }
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO job_preferences (id, "userId", "jobType", skills, "preferredLocation",
        "expectedSalary", "salaryNegotiable", "employmentType", "experienceYears", "noticePeriod", "isActive", "isPaid", "paidUntil")
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8::job_preferences_employmenttype_enum,$9,$10::job_preferences_noticeperiod_enum,
        true,$11,CASE WHEN $11 THEN NOW() + INTERVAL '30 days' ELSE NULL END)"#)
        .bind(id).bind(uid).bind(&input.job_type).bind(input.skills.join(","))
        .bind(&input.preferred_location).bind(input.salary()).bind(input.salary_negotiable)
        .bind(&input.employment_type).bind(input.experience_years).bind(&input.notice_period).bind(paid)
        .execute(&mut *tx).await?;
    if let Some(payment_id)=payment_id {record_receipt(&mut tx,payment_id,id).await?;}
    let row = sqlx::query(&format!(
        "SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE id = $1"
    ))
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(super::pref_json(&row))
}

async fn record_receipt(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,payment:Uuid,profile:Uuid)->AppResult<()> {
    sqlx::query(r#"INSERT INTO career_profile_receipts ("paymentOrderId","preferenceId") VALUES ($1,$2)"#)
        .bind(payment).bind(profile).execute(&mut **tx).await?;Ok(())
}

pub(super) async fn update(
    state: &AppState,
    user_id: &str,
    id: &str,
    body: &Value,
) -> AppResult<Value> {
    let pid = Uuid::parse_str(id)?;
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(&format!(r#"SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE id = $1 AND "userId" = $2 AND "isActive" = true FOR UPDATE"#))
        .bind(pid).bind(Uuid::parse_str(user_id)?).fetch_optional(&mut *tx).await?
        .ok_or_else(|| AppError::NotFound("Career profile not found on your account".into()))?;
    let mut merged = super::pref_json(&row);
    // Money is serialized as a string for API precision; validation accepts
    // the client's numeric form, so convert the existing value for this merge.
    merged["expectedSalary"] = json!(row
        .get::<Decimal, _>("expectedSalary")
        .to_string()
        .parse::<f64>()
        .unwrap_or(0.0));
    let fields = body
        .as_object()
        .ok_or_else(|| AppError::BadRequest("Expected profile object".into()))?;
    for (key, value) in fields {
        merged[key] = value.clone();
    }
    let input = Preference::parse(&merged)?;
    if !input
        .job_type
        .eq_ignore_ascii_case(&row.get::<String, _>("jobType"))
    {
        return Err(AppError::BadRequest(
            "Job type cannot be changed after creation".into(),
        ));
    }
    sqlx::query(r#"UPDATE job_preferences SET skills = $1, "preferredLocation" = $2, "expectedSalary" = $3,
        "salaryNegotiable" = $4, "employmentType" = $5::job_preferences_employmenttype_enum,
        "experienceYears" = $6, "noticePeriod" = $7::job_preferences_noticeperiod_enum, "updatedAt" = NOW() WHERE id = $8"#)
        .bind(input.skills.join(",")).bind(&input.preferred_location).bind(input.salary())
        .bind(input.salary_negotiable).bind(&input.employment_type).bind(input.experience_years)
        .bind(&input.notice_period).bind(pid).execute(&mut *tx).await?;
    let row = sqlx::query(&format!(
        "SELECT {JOB_PREFERENCE_COLS} FROM job_preferences WHERE id = $1"
    ))
    .bind(pid)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(super::pref_json(&row))
}

pub(super) async fn delete(state: &AppState, user_id: &str, id: &str) -> AppResult<()> {
    let result = sqlx::query(r#"UPDATE job_preferences SET "isActive" = false, "updatedAt" = NOW()
        WHERE id = $1 AND "userId" = $2 AND "isActive" = true AND "createdAt" <= timezone('UTC', NOW()) - INTERVAL '7 days'"#)
        .bind(Uuid::parse_str(id)?).bind(Uuid::parse_str(user_id)?).execute(&state.db).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest(
            "Only your active profiles older than seven days can be deleted".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn employment_codes_and_criteria_are_validated() {
        assert_eq!(
            employment_type(Some("FULL_TIME")).unwrap().as_deref(),
            Some("FT")
        );
        assert_eq!(
            employment_type(Some("Internship")).unwrap().as_deref(),
            Some("INTERN")
        );
        assert!(Preference::parse(&json!({"jobType":"Cook", "expectedSalary":-1})).is_err());
        assert!(Preference::parse(&json!({"jobType":"Cook", "noticePeriod":"TOMORROW"})).is_err());
        assert!(Preference::parse(&json!({"jobType":" ", "expectedSalary":500})).is_err());
        assert!(Preference::parse(
            &json!({"jobType":"Cook", "skills":["Kerala cuisine"], "expectedSalary":18000})
        )
        .is_ok());
    }
}
