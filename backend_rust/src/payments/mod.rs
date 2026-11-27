use axum::{
    body::Bytes,
    extract::State,
    http::HeaderMap,
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::Sha256;
use sqlx::Row;
use tracing::{error, info, warn};
use uuid::Uuid;

use crate::bookings::cancel::{
    get_late_cancel_compensation_quote, mark_late_cancel_compensation_paid,
};
use crate::common::money::WALLET_PAYMENTS_ENABLED;
use crate::config::is_real_secret;
use crate::error::{AppError, AppResult};
use crate::matching::{
    create_preference_from_payment, create_request_from_payment, preference_count,
    quote_match_fee,
};
use crate::middleware::auth::{require_admin, AuthUser};
use crate::state::AppState;
use crate::wallets::add_funds;
use crate::workers::{mark_period_fee_paid, periodic_jobs_per_payment};

type HmacSha256 = Hmac<Sha256>;
mod recovery;
pub(crate) use recovery::run_reconciliation;

const PURPOSE_WALLET_RECHARGE: &str = "WALLET_RECHARGE";
const PURPOSE_PERIOD_FEE: &str = "PERIOD_FEE";
const PURPOSE_LATE_CANCEL: &str = "LATE_CANCEL_COMPENSATION";
const PURPOSE_HIRING_MATCH: &str = "HIRING_MATCH_FEE";
const PURPOSE_EXTRA_JOB_TYPE: &str = "EXTRA_JOB_TYPE_FEE";
pub(crate) const PURPOSE_RENTAL_ADVANCE: &str = "RENTAL_ADVANCE";
pub(crate) const PURPOSE_RENTAL_SETTLEMENT: &str = "RENTAL_SETTLEMENT";

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/gateway-status", get(gateway_status))
        .route("/recharge/order", post(create_recharge_order))
        .route("/period-fee/order", post(create_period_fee_order))
        .route("/late-cancel-compensation/order", post(create_late_cancel_order))
        .route("/hiring-match/order", post(create_hiring_match_order))
        .route("/extra-job-type/order", post(create_extra_job_type_order))
        .route("/pending", get(recovery::pending))
        .route("/orders/{id}", get(recovery::status))
        .route("/orders/{id}/verify", post(recovery::verify))
        .route("/admin/refund-failures", get(admin_refund_failures))
        .route("/webhook", post(webhook))
}

fn razorpay_configured(state: &AppState) -> bool {
    is_real_secret(state.config.razorpay_key_id.as_deref())
        && is_real_secret(state.config.razorpay_key_secret.as_deref())
}

/// Actionable refund queue for admins (late rental captures, provider failures).
async fn admin_refund_failures(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    require_admin(&user)?;
    let rows = sqlx::query(
        r#"SELECT id, "userId", amount, purpose::text AS purpose, status::text AS status,
                  "razorpayOrderId", "razorpayPaymentId", meta, "refundFailure",
                  "createdAt", "updatedAt", "refundedAt"
           FROM payment_orders
           WHERE status::text IN ('REFUND_REQUIRED','REFUND_PENDING')
              OR ("refundFailure" IS NOT NULL AND status::text <> 'REFUNDED')
           ORDER BY "updatedAt" DESC
           LIMIT 100"#,
    )
    .fetch_all(&state.db)
    .await?;
    let items: Vec<Value> = rows
        .iter()
        .map(|r| {
            json!({
                "id": r.get::<Uuid, _>("id"),
                "userId": r.get::<Uuid, _>("userId"),
                "amount": r.get::<rust_decimal::Decimal, _>("amount"),
                "purpose": r.get::<String, _>("purpose"),
                "status": r.get::<String, _>("status"),
                "razorpayOrderId": r.try_get::<Option<String>, _>("razorpayOrderId").ok().flatten(),
                "razorpayPaymentId": r.try_get::<Option<String>, _>("razorpayPaymentId").ok().flatten(),
                "meta": r.try_get::<Option<Value>, _>("meta").ok().flatten(),
                "refundFailure": r.try_get::<Option<String>, _>("refundFailure").ok().flatten(),
                "createdAt": crate::common::pg::date_json(r, "createdAt"),
                "updatedAt": crate::common::pg::date_json(r, "updatedAt"),
                "refundedAt": crate::common::pg::date_json(r, "refundedAt"),
            })
        })
        .collect();
    Ok(Json(json!({ "items": items })))
}

async fn gateway_status(State(state): State<AppState>) -> Json<Value> {
    let configured = razorpay_configured(&state);
    Json(json!({
        "wallet": {
            "available": WALLET_PAYMENTS_ENABLED,
            "message": if WALLET_PAYMENTS_ENABLED { Value::Null } else { json!("Gixbee Wallet is off — pay the pro directly (cash/UPI).") }
        },
        "cash": { "available": true },
        "razorpay": {
            "available": configured,
            "needsApiKey": !configured,
            "message": if configured { Value::Null } else { json!("Razorpay not configured — set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET") }
        },
        "upi": {
            "available": false,
            "provider": "PHONEPE",
            "needsApiKey": true,
            "message": "In-app UPI gateway not configured — use cash/UPI with the pro, or Razorpay for period fee / late-cancel."
        }
    }))
}

#[derive(Deserialize)]
struct AmountBody {
    amount: f64,
}

#[derive(Deserialize)]
struct HiringMatchBody {
    businessId: Option<Uuid>,
    jobType: String,
    skills: Option<Vec<String>>,
    location: Option<String>,
    salaryOffered: Option<f64>,
    salaryMin: Option<f64>,
    salaryMax: Option<f64>,
    salaryNegotiable: Option<bool>,
    employmentType: Option<String>,
    experienceMinYears: Option<i32>,
    vacancies: Option<i32>,
    sectorId: Option<String>,
    positionId: Option<String>,
    specializationIds: Option<Vec<String>>,
    skillIds: Option<Vec<String>>,
    qualificationId: Option<String>,
    qualificationRequired: Option<bool>,
    salaryPeriod: Option<String>,
    locationId: Option<String>,
    addressText: Option<String>,
    workMode: Option<String>,
    description: Option<String>,
    languageIds: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct ExtraJobTypeBody {
    seekerDetails: Option<Value>,
    renewPreferenceId:Option<Uuid>,
    jobType: String,
    skills: Option<Vec<String>>,
    preferredLocation: Option<String>,
    expectedSalary: Option<f64>,
    salaryNegotiable: Option<bool>,
    employmentType: Option<String>,
    experienceYears: Option<i32>,
    noticePeriod: Option<String>,
    sectorId: Option<String>,
    positionId: Option<String>,
    specializationIds: Option<Vec<String>>,
    skillIds: Option<Vec<String>>,
    qualificationId: Option<String>,
    locationId: Option<String>,
    addressText: Option<String>,
    expectedSalaryPeriod: Option<String>,
    languageIds: Option<Vec<String>>,
}

async fn create_recharge_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<AmountBody>,
) -> AppResult<Json<Value>> {
    if !WALLET_PAYMENTS_ENABLED {
        return Err(AppError::BadRequest(
            "Wallet payments are disabled".into(),
        ));
    }
    let rupees = body.amount.round() as i32;
    if rupees < 10 || rupees > 100_000 {
        return Err(AppError::BadRequest(
            "Recharge amount must be between ₹10 and ₹1,00,000.".into(),
        ));
    }
    create_razorpay_order(&state, &user.user_id, PURPOSE_WALLET_RECHARGE, rupees, None).await
}

async fn create_period_fee_order(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    let jobs_included = periodic_jobs_per_payment(&state).await;
    if jobs_included <= 0 {
        return Err(AppError::BadRequest(
            "The per-jobs payment plan is not enabled.".into(),
        ));
    }
    let fee = config_number(&state, "go_live_period_fee", 49).await;
    if fee <= 0 {
        return Err(AppError::BadRequest("No fee is configured for the plan.".into()));
    }
    create_razorpay_order(&state, &user.user_id, PURPOSE_PERIOD_FEE, fee, None).await
}

async fn create_late_cancel_order(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    let quote = get_late_cancel_compensation_quote(&state, &user.user_id).await?;
    let blocked = quote.get("blocked").and_then(|v| v.as_bool()).unwrap_or(false);
    let amount = quote.get("amountInr").and_then(|v| v.as_i64());
    if !blocked || amount.unwrap_or(0) <= 0 {
        return Err(AppError::BadRequest(
            "No travel compensation is due — Instant Help is not blocked.".into(),
        ));
    }
    create_razorpay_order(
        &state,
        &user.user_id,
        PURPOSE_LATE_CANCEL,
        amount.unwrap_or(0) as i32,
        None,
    )
    .await
}

async fn create_hiring_match_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<HiringMatchBody>,
) -> AppResult<Json<Value>> {
    let job_type = body.jobType.trim();
    if job_type.is_empty() {
        return Err(AppError::BadRequest("jobType is required".into()));
    }
    let vacancies = body.vacancies.unwrap_or(1).max(1);
    let (fee, credit_applied, amount_due) =
        quote_match_fee(&state, &user.user_id, vacancies).await?;
    if amount_due <= 0 {
        return Err(AppError::BadRequest(
            "No payment due — create the hiring request directly (credit covers the fee).".into(),
        ));
    }
    let salary_offered = body.salaryOffered.unwrap_or(0.0);
    let salary_min = body.salaryMin.unwrap_or(0.0);
    let salary_max = body.salaryMax.unwrap_or(salary_offered);
    let mut meta = json!({
        "businessId":body.businessId,
        "jobType": job_type,
        "skills": body.skills.unwrap_or_default(),
        "location": body.location,
        "salaryOffered": salary_offered,
        "salaryMin": salary_min,
        "salaryMax": salary_max,
        "salaryNegotiable": body.salaryNegotiable.unwrap_or(false),
        "employmentType": body.employmentType.as_deref().unwrap_or("FULL_TIME"),
        "experienceMinYears": body.experienceMinYears.unwrap_or(0),
        "vacancies": vacancies,
        "fee": fee,
        "creditApplied": credit_applied,
        "sectorId": body.sectorId,
        "positionId": body.positionId,
        "specializationIds": body.specializationIds.unwrap_or_default(),
        "skillIds": body.skillIds.unwrap_or_default(),
        "qualificationId": body.qualificationId,
        "qualificationRequired": body.qualificationRequired.unwrap_or(false),
        "salaryPeriod": body.salaryPeriod,
        "locationId": body.locationId,
        "addressText": body.addressText,
        "workMode": body.workMode,
        "description": body.description,
        "languageIds": body.languageIds.unwrap_or_default(),
    });
    crate::matching::validate_request(&meta)?;
    crate::matching::validate_catalogue(&state, &meta).await?;
    meta["businessId"]=json!(crate::matching::resolve_business(&state,&user.user_id,&meta).await?);
    let Json(mut response) = create_razorpay_order(
        &state,
        &user.user_id,
        PURPOSE_HIRING_MATCH,
        amount_due,
        Some(meta),
    )
    .await?;
    if let Some(obj) = response.as_object_mut() {
        obj.insert("fee".into(), json!(fee));
        obj.entry("creditApplied").or_insert(json!(credit_applied));
        obj.entry("amountDue").or_insert(json!(amount_due));
    }
    Ok(Json(response))
}

async fn create_extra_job_type_order(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ExtraJobTypeBody>,
) -> AppResult<Json<Value>> {
    let job_type = body.jobType.trim();
    if job_type.is_empty() {
        return Err(AppError::BadRequest("jobType is required".into()));
    }
    let existing = preference_count(&state, &user.user_id).await?;
    if existing < 2 && body.renewPreferenceId.is_none() {
        return Err(AppError::BadRequest(
            "Your first two Job Types are free — create them without payment.".into(),
        ));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    let duplicate: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM job_preferences
           WHERE "userId" = $1 AND LOWER("jobType") = LOWER($2) AND "isActive" = true LIMIT 1"#,
    )
    .bind(uid)
    .bind(job_type)
    .fetch_optional(&state.db)
    .await?;
    if duplicate.is_some() && duplicate!=body.renewPreferenceId {
        return Err(AppError::BadRequest(
            "You already have a profile for this Job Type".into(),
        ));
    }
    if let Some(profile)=body.renewPreferenceId {
        let renew:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM job_preferences WHERE id=$1 AND "userId"=$2 AND "isActive"=true AND "isPaid"=true AND LOWER("jobType")=LOWER($3))"#)
            .bind(profile).bind(uid).bind(job_type).fetch_one(&state.db).await?;
        if !renew {return Err(AppError::BadRequest("Select your paid career profile to renew".into()));}
    }
    let fee = crate::master_admin::plan_value(&state.db, "extra_profile_fee").await?;
    let days = crate::master_admin::plan_value(&state.db, "extra_profile_days").await?;
    let meta = json!({
        "durationDays": days,
        "renewPreferenceId":body.renewPreferenceId,
        "seekerDetails":body.seekerDetails,
        "jobType": job_type,
        "skills": body.skills.unwrap_or_default(),
        "preferredLocation": body.preferredLocation,
        "expectedSalary": body.expectedSalary.unwrap_or(0.0),
        "salaryNegotiable": body.salaryNegotiable.unwrap_or(false),
        "employmentType": body.employmentType.as_deref().unwrap_or("FULL_TIME"),
        "experienceYears": body.experienceYears.unwrap_or(0),
        "noticePeriod": body.noticePeriod.as_deref().unwrap_or("IMMEDIATE"),
        "sectorId": body.sectorId,
        "positionId": body.positionId,
        "specializationIds": body.specializationIds.unwrap_or_default(),
        "skillIds": body.skillIds.unwrap_or_default(),
        "qualificationId": body.qualificationId,
        "locationId": body.locationId,
        "addressText": body.addressText,
        "expectedSalaryPeriod": body.expectedSalaryPeriod,
        "languageIds": body.languageIds.unwrap_or_default(),
    });
    crate::matching::validate_preference(&meta)?;
    if let Some(profile_id) = body.renewPreferenceId {
        crate::matching::validate_renewal_profile_catalogue(&state, &meta, profile_id, uid)
            .await?;
    } else {
        crate::matching::validate_seeker_checkout(&state, &meta, uid).await?;
        crate::matching::validate_profile_catalogue(&state, &meta).await?;
    }
    create_razorpay_order(&state, &user.user_id, PURPOSE_EXTRA_JOB_TYPE, fee, Some(meta)).await
}

pub(crate) async fn create_razorpay_order(
    state: &AppState,
    user_id: &str,
    purpose: &str,
    rupees: i32,
    meta: Option<Value>,
) -> AppResult<Json<Value>> {
    if !razorpay_configured(state) {
        return Err(AppError::BadRequest(
            "Online payment is not available yet — payment gateway is not configured on the server.".into(),
        ));
    }

    let key_id = state.config.razorpay_key_id.as_deref().unwrap_or("");
    let key_secret = state.config.razorpay_key_secret.as_deref().unwrap_or("");
    let receipt_prefix = match purpose {
        "JOB_CREDITS" => "pack",
        crate::plans::PURPOSE => "pln",
        PURPOSE_PERIOD_FEE => "fee",
        PURPOSE_LATE_CANCEL => "lcc",
        PURPOSE_HIRING_MATCH => "hmf",
        PURPOSE_EXTRA_JOB_TYPE => "ejt",
        PURPOSE_RENTAL_ADVANCE => "rad",
        PURPOSE_RENTAL_SETTLEMENT => "rst",
        _ => "rcg",
    };

    let uid = Uuid::parse_str(user_id)?;
    let hiring_basic = if purpose == PURPOSE_HIRING_MATCH {
        Some(crate::master_admin::plan_value(&state.db, "hiring_basic_limit").await?)
    } else {
        None
    };

    // 1) Short transaction: reserve intent / resume existing checkout. No HTTP here.
    let mut tx = state.db.begin().await?;
    let lock_sql = if [PURPOSE_HIRING_MATCH, PURPOSE_EXTRA_JOB_TYPE, crate::plans::PURPOSE]
        .contains(&purpose)
    {
        "SELECT id FROM users WHERE id=$1 FOR UPDATE"
    } else {
        "SELECT id FROM users WHERE id=$1 FOR NO KEY UPDATE"
    };
    sqlx::query(lock_sql)
        .bind(uid)
        .fetch_one(&mut *tx)
        .await?;

    if [PURPOSE_HIRING_MATCH, PURPOSE_EXTRA_JOB_TYPE, crate::plans::PURPOSE].contains(&purpose) {
        let existing = sqlx::query(
            r#"SELECT id, "razorpayOrderId", amount, meta FROM payment_orders WHERE "userId"=$1
            AND purpose::text=$2 AND status='CREATED' AND (meta-'fee'-'creditApplied'-'durationDays')=($3::jsonb-'fee'-'creditApplied'-'durationDays')
            AND ($2 <> 'PLATFORM_PLAN' OR amount=$4)
            ORDER BY "createdAt" DESC LIMIT 1"#,
        )
        .bind(uid)
        .bind(purpose)
        .bind(&meta)
        .bind(rupees)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(existing) = existing {
            if let Some(order_id) = existing
                .try_get::<Option<String>, _>("razorpayOrderId")
                .ok()
                .flatten()
            {
                let due = existing.get::<rust_decimal::Decimal, _>("amount");
                let saved: Value = existing.get("meta");
                tx.commit().await?;
                return Ok(Json(json!({
                    "orderId": order_id,
                    "amount": rust_decimal::prelude::ToPrimitive::to_i64(&(due * rust_decimal::Decimal::from(100))),
                    "amountDue": rust_decimal::prelude::ToPrimitive::to_i32(&due),
                    "creditApplied": saved["creditApplied"],
                    "currency": "INR",
                    "keyId": key_id,
                    "paymentOrderId": existing.get::<Uuid, _>("id"),
                    "resumed": true,
                })));
            }
            // Intent exists without provider id — reuse it below.
            let intent_id: Uuid = existing.get("id");
            if let Some(basic) = hiring_basic {
                let business = meta
                    .as_ref()
                    .and_then(|m| m["businessId"].as_str())
                    .ok_or_else(|| AppError::BadRequest("Hiring business is required".into()))?;
                crate::plans::check_hiring_limit(&mut tx, uid, Uuid::parse_str(business)?, basic)
                    .await?;
                let balance: rust_decimal::Decimal = sqlx::query_scalar(
                    r#"SELECT "hiringCreditBalance" FROM users WHERE id=$1 FOR UPDATE"#,
                )
                .bind(uid)
                .fetch_one(&mut *tx)
                .await?;
                let reserved = crate::matching::reserved_hiring_credit(&mut *tx, uid, None).await?;
                let applied = meta
                    .as_ref()
                    .and_then(|v| v.get("creditApplied"))
                    .and_then(Value::as_i64)
                    .unwrap_or(0);
                if balance - reserved < rust_decimal::Decimal::from(applied) {
                    return Err(AppError::Conflict(
                        "Hiring credit changed. Refresh the payment quote.".into(),
                    ));
                }
            }
            tx.commit().await?;
            return attach_razorpay_order(
                state,
                intent_id,
                user_id,
                purpose,
                rupees,
                key_id,
                key_secret,
                receipt_prefix,
            )
            .await;
        }
    }

    if matches!(
        purpose,
        PURPOSE_PERIOD_FEE | PURPOSE_LATE_CANCEL | PURPOSE_RENTAL_ADVANCE | PURPOSE_RENTAL_SETTLEMENT
    ) {
        let existing = sqlx::query(
            r#"SELECT id, "razorpayOrderId" FROM payment_orders
               WHERE "userId"=$1 AND purpose::text=$2 AND amount=$3
                 AND meta IS NOT DISTINCT FROM $4::jsonb AND status='CREATED'
                 AND "createdAt">NOW()-INTERVAL '24 hours'
               ORDER BY "createdAt" DESC LIMIT 1"#,
        )
        .bind(uid)
        .bind(purpose)
        .bind(rupees)
        .bind(&meta)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(existing) = existing {
            if let Some(order_id) = existing
                .try_get::<Option<String>, _>("razorpayOrderId")
                .ok()
                .flatten()
            {
                tx.commit().await?;
                return Ok(Json(json!({
                    "orderId": order_id,
                    "amount": rupees * 100,
                    "currency": "INR",
                    "keyId": key_id,
                    "paymentOrderId": existing.get::<Uuid, _>("id"),
                    "resumed": true,
                })));
            }
            let intent_id: Uuid = existing.get("id");
            tx.commit().await?;
            return attach_razorpay_order(
                state,
                intent_id,
                user_id,
                purpose,
                rupees,
                key_id,
                key_secret,
                receipt_prefix,
            )
            .await;
        }
    }

    if let Some(basic) = hiring_basic {
        let business = meta
            .as_ref()
            .and_then(|m| m["businessId"].as_str())
            .ok_or_else(|| AppError::BadRequest("Hiring business is required".into()))?;
        crate::plans::check_hiring_limit(&mut tx, uid, Uuid::parse_str(business)?, basic).await?;
        let balance: rust_decimal::Decimal = sqlx::query_scalar(
            r#"SELECT "hiringCreditBalance" FROM users WHERE id=$1 FOR UPDATE"#,
        )
        .bind(uid)
        .fetch_one(&mut *tx)
        .await?;
        let reserved = crate::matching::reserved_hiring_credit(&mut *tx, uid, None).await?;
        let applied = meta
            .as_ref()
            .and_then(|v| v.get("creditApplied"))
            .and_then(Value::as_i64)
            .unwrap_or(0);
        if balance - reserved < rust_decimal::Decimal::from(applied) {
            return Err(AppError::Conflict(
                "Hiring credit changed. Refresh the payment quote.".into(),
            ));
        }
    }

    let intent_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO payment_orders (id, "userId", purpose, amount, status, "razorpayOrderId", meta)
           VALUES ($1, $2, $3::payment_orders_purpose_enum, $4, 'CREATED', NULL, $5)"#,
    )
    .bind(intent_id)
    .bind(uid)
    .bind(purpose)
    .bind(rupees)
    .bind(&meta)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    attach_razorpay_order(
        state,
        intent_id,
        user_id,
        purpose,
        rupees,
        key_id,
        key_secret,
        receipt_prefix,
    )
    .await
}

async fn attach_razorpay_order(
    state: &AppState,
    intent_id: Uuid,
    user_id: &str,
    purpose: &str,
    rupees: i32,
    key_id: &str,
    key_secret: &str,
    receipt_prefix: &str,
) -> AppResult<Json<Value>> {
    // Recover if a previous attempt already attached a provider order.
    if let Some(existing) = sqlx::query_scalar::<_, String>(
        r#"SELECT "razorpayOrderId" FROM payment_orders
           WHERE id=$1 AND status='CREATED' AND "razorpayOrderId" IS NOT NULL"#,
    )
    .bind(intent_id)
    .fetch_optional(&state.db)
    .await?
    {
        return Ok(Json(json!({
            "orderId": existing,
            "amount": rupees * 100,
            "currency": "INR",
            "keyId": key_id,
            "paymentOrderId": intent_id,
            "resumed": true,
        })));
    }

    let receipt = format!("{}_{}", receipt_prefix, intent_id.simple());
    let auth = STANDARD.encode(format!("{}:{}", key_id, key_secret));
    let res = state
        .http
        .post("https://api.razorpay.com/v1/orders")
        .timeout(std::time::Duration::from_secs(20))
        .header("Authorization", format!("Basic {}", auth))
        .json(&json!({
            "amount": rupees * 100,
            "currency": "INR",
            "receipt": receipt,
            "notes": {
                "gixbeeUserId": user_id,
                "purpose": purpose,
                "gixbeePaymentOrderId": intent_id.to_string(),
            },
        }))
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("Razorpay request failed: {}", e)))?;

    if !res.status().is_success() {
        let status = res.status();
        let detail = res.text().await.unwrap_or_default();
        error!(
            "[Razorpay] order create failed ({}): {}",
            status,
            detail.chars().take(500).collect::<String>()
        );
        return Err(AppError::BadRequest(
            "Could not start the payment — please try again in a moment.".into(),
        ));
    }

    let order: Value = res
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("Razorpay response parse failed: {}", e)))?;
    let razorpay_order_id = order
        .get("id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::Internal("Razorpay order id missing".into()))?
        .to_string();

    // 2) Short transaction: attach provider id (idempotent if webhook/reconcile raced).
    let mut tx = state.db.begin().await?;
    let attached = sqlx::query(
        r#"UPDATE payment_orders
           SET "razorpayOrderId" = $2, "updatedAt" = NOW()
           WHERE id = $1 AND status = 'CREATED'
             AND ("razorpayOrderId" IS NULL OR "razorpayOrderId" = $2)"#,
    )
    .bind(intent_id)
    .bind(&razorpay_order_id)
    .execute(&mut *tx)
    .await?;
    if attached.rows_affected() == 0 {
        let current: Option<String> = sqlx::query_scalar(
            r#"SELECT "razorpayOrderId" FROM payment_orders WHERE id=$1"#,
        )
        .bind(intent_id)
        .fetch_optional(&mut *tx)
        .await?
        .flatten();
        tx.commit().await?;
        if let Some(existing) = current {
            return Ok(Json(json!({
                "orderId": existing,
                "amount": rupees * 100,
                "currency": "INR",
                "keyId": key_id,
                "paymentOrderId": intent_id,
                "resumed": true,
            })));
        }
        return Err(AppError::Conflict(
            "Checkout changed. Refresh and try again.".into(),
        ));
    }
    tx.commit().await?;

    info!(
        "[Razorpay] order {} attached to intent {} — ₹{} {} for {}",
        razorpay_order_id, intent_id, rupees, purpose, user_id
    );

    Ok(Json(json!({
        "orderId": razorpay_order_id,
        "amount": rupees * 100,
        "currency": "INR",
        "keyId": key_id,
        "paymentOrderId": intent_id,
    })))
}

async fn config_number(state: &AppState, key: &str, fallback: i32) -> i32 {
    let raw: Option<String> = sqlx::query_scalar(
        r#"SELECT value FROM master_entries
           WHERE type::text = 'CONFIGURATION' AND label = $1 AND "isActive" = true LIMIT 1"#,
    )
    .bind(key)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    match raw {
        Some(s) => s
            .trim()
            .parse::<i32>()
            .ok()
            .filter(|n| *n >= 0)
            .unwrap_or(fallback),
        None => fallback,
    }
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

fn verify_webhook_signature(secret: &str, raw: &[u8], signature: &str) -> bool {
    if secret.is_empty() || signature.is_empty() {
        return false;
    }
    let mut mac = match HmacSha256::new_from_slice(secret.as_bytes()) {
        Ok(m) => m,
        Err(_) => return false,
    };
    mac.update(raw);
    let expected = hex::encode(mac.finalize().into_bytes());
    constant_time_eq(expected.as_bytes(), signature.as_bytes())
}

async fn webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> AppResult<Json<Value>> {
    if body.is_empty() {
        return Err(AppError::BadRequest("Missing request body".into()));
    }

    let signature = headers
        .get("x-razorpay-signature")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let secret = state.config.razorpay_webhook_secret.as_deref().unwrap_or("");
    if !verify_webhook_signature(secret, &body, signature) {
        warn!("[Razorpay] webhook signature mismatch — rejected");
        return Err(AppError::Forbidden("Invalid signature".into()));
    }

    let event: Value = serde_json::from_slice(&body)
        .map_err(|_| AppError::BadRequest("Invalid JSON".into()))?;
    let event_type = event.get("event").and_then(|v| v.as_str()).unwrap_or("");
    if event_type != "payment.captured" && event_type != "order.paid" {
        return Ok(Json(json!({ "ok": true, "ignored": event_type })));
    }

    let payment = event.pointer("/payload/payment/entity");
    let order_id = payment
        .and_then(|p| p.get("order_id"))
        .and_then(|v| v.as_str())
        .or_else(|| {
            event
                .pointer("/payload/order/entity/id")
                .and_then(|v| v.as_str())
        });
    let payment_id = payment
        .and_then(|p| p.get("id"))
        .and_then(|v| v.as_str());

    let order_id = match order_id {
        Some(id) => id,
        None => return Ok(Json(json!({ "ok": true, "ignored": "no order id" }))),
    };

    if let Some(payment) = payment {
        if crate::billing::purchases::fulfil(&state, payment, None)
            .await?
            .is_some()
        {
            return Ok(Json(json!({ "ok": true })));
        }
        // Razorpay can fire payment.captured before our INSERT commits.
        // 503 asks them to retry instead of treating a missing pack row as a duplicate.
        if payment
            .pointer("/notes/purpose")
            .and_then(|v| v.as_str())
            == Some("JOB_CREDITS")
        {
            return Err(AppError::ServiceUnavailable(
                "credit pack order not persisted yet".into(),
            ));
        }
    }

    // Hiring fulfillment is independently idempotent. Keep CREATED until its
    // database effects commit, so a crash is retryable and reserved credit is
    // never briefly exposed to another request while fulfillment is in flight.
    let hiring_order = sqlx::query(r#"SELECT id,"userId",amount,purpose::text AS purpose,meta,status::text AS status
        FROM payment_orders WHERE "razorpayOrderId"=$1 AND purpose::text IN ('HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','PLATFORM_PLAN')"#)
        .bind(order_id).fetch_optional(&state.db).await?;
    if let Some(order) = hiring_order {
        if order.get::<String,_>("status") == "CREDITED" { return Ok(Json(json!({"ok":true,"duplicate":true}))); }
        if order.get::<String,_>("status") != "CREATED" { return Err(AppError::Conflict("Payment order is not payable".into())); }
        let payment = payment.ok_or_else(||AppError::ServiceUnavailable("Captured payment details are required".into()))?;
        let amount = order.get::<rust_decimal::Decimal,_>("amount");
        if payment.get("status").and_then(Value::as_str) != Some("captured")
            || payment.get("currency").and_then(Value::as_str) != Some("INR")
            || payment.get("amount").and_then(Value::as_i64).map(rust_decimal::Decimal::from) != Some(amount * rust_decimal::Decimal::from(100)) {
            return Err(AppError::BadRequest("Captured payment does not match the order".into()));
        }
        let purpose = order.get::<String,_>("purpose");
        let meta = order.get::<Option<Value>,_>("meta");
        fulfil_order(&state,order_id,&order.get::<Uuid,_>("userId").to_string(),
            rust_decimal::prelude::ToPrimitive::to_i32(&amount).unwrap_or(0),&purpose,meta.as_ref(),order.get("id"),payment_id).await?;
        sqlx::query(r#"UPDATE payment_orders SET status='CREDITED',"razorpayPaymentId"=$2 WHERE id=$1 AND status='CREATED'"#)
            .bind(order.get::<Uuid,_>("id")).bind(payment_id).execute(&state.db).await?;
        return Ok(Json(json!({"ok":true})));
    }
    if matches!(payment.and_then(|p|p.pointer("/notes/purpose")).and_then(Value::as_str),Some("HIRING_MATCH_FEE"|"EXTRA_JOB_TYPE_FEE"|"PLATFORM_PLAN")) {
        return Err(AppError::ServiceUnavailable("Payment order not persisted yet".into()));
    }

    let payment = payment.ok_or_else(|| AppError::ServiceUnavailable("Captured payment details are required".into()))?;

    // If the webhook wins the race before attach, bind by durable intent id from notes.
    if sqlx::query_scalar::<_, bool>(
        r#"SELECT EXISTS(SELECT 1 FROM payment_orders WHERE "razorpayOrderId"=$1)"#,
    )
    .bind(order_id)
    .fetch_one(&state.db)
    .await?
        == false
    {
        if let Some(intent) = payment
            .pointer("/notes/gixbeePaymentOrderId")
            .and_then(Value::as_str)
            .and_then(|s| Uuid::parse_str(s).ok())
        {
            let attached = sqlx::query(
                r#"UPDATE payment_orders
                   SET "razorpayOrderId"=$2, "updatedAt"=NOW()
                   WHERE id=$1 AND status='CREATED'
                     AND ("razorpayOrderId" IS NULL OR "razorpayOrderId"=$2)"#,
            )
            .bind(intent)
            .bind(order_id)
            .execute(&state.db)
            .await?;
            if attached.rows_affected() == 0 {
                return Err(AppError::ServiceUnavailable(
                    "Payment order not persisted yet".into(),
                ));
            }
        } else {
            return Err(AppError::ServiceUnavailable(
                "Payment order not persisted yet".into(),
            ));
        }
    }

    let amount: rust_decimal::Decimal = sqlx::query_scalar(
        r#"SELECT amount FROM payment_orders WHERE "razorpayOrderId"=$1"#,
    )
    .bind(order_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::ServiceUnavailable("Payment order not persisted yet".into()))?;
    captured_payment_id(payment, order_id, amount)?;
    // Keep the signed capture durable while rental or fee fulfillment is retried.
    sqlx::query(
        r#"INSERT INTO outbox_events (id, type, "aggregateId", payload)
           SELECT id, 'payment.captured', id, $2
           FROM payment_orders WHERE "razorpayOrderId"=$1 AND status IN ('CREATED','REFUND_REQUIRED')
           ON CONFLICT (id) DO NOTHING"#,
    )
    .bind(order_id)
    .bind(json!({"orderId": order_id, "payment": {
        "id": payment["id"], "order_id": payment["order_id"], "status": payment["status"],
        "amount": payment["amount"], "currency": payment["currency"],
    }}))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({ "ok": true })))
}

fn captured_payment_id<'a>(
    payment: &'a Value,
    order_id: &str,
    amount: rust_decimal::Decimal,
) -> AppResult<&'a str> {
    let payment_id = payment.get("id").and_then(Value::as_str)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| AppError::BadRequest("Missing captured payment reference".into()))?;
    if payment["status"].as_str() != Some("captured") || payment["currency"].as_str() != Some("INR")
        || payment["order_id"].as_str() != Some(order_id)
        || payment["amount"].as_i64().map(rust_decimal::Decimal::from) != Some(amount * rust_decimal::Decimal::from(100)) {
        return Err(AppError::BadRequest("Captured payment does not match the order".into()));
    }
    Ok(payment_id)
}

pub(crate) async fn apply_legacy_payment(state: &AppState, order_id: &str, payment: &Value) -> AppResult<()> {
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        r#"SELECT id, "userId", amount, purpose::text AS purpose, meta, status::text AS status
           FROM payment_orders WHERE "razorpayOrderId"=$1 FOR UPDATE"#,
    )
    .bind(order_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::ServiceUnavailable("Payment order not persisted yet".into()))?;
    let status = row.get::<String, _>("status");
    if status == "CREDITED" || status == "REFUNDED" || status == "REFUND_PENDING" {
        return Ok(());
    }
    if status == "REFUND_REQUIRED" {
        // Already marked — ensure refund outbox exists and exit cleanly.
        let id: Uuid = row.get("id");
        enqueue_refund_required(&mut tx, id, order_id, payment).await?;
        tx.commit().await?;
        return Ok(());
    }
    if status != "CREATED" {
        return Err(AppError::Conflict("Payment order is not payable".into()));
    }
    let payment_id = captured_payment_id(payment, order_id, row.get("amount"))?;
    let id: Uuid = row.get("id");
    let user_id: Uuid = row.get("userId");
    let meta: Option<Value> = row.get("meta");
    let purpose = row.get::<String, _>("purpose");
    let apply_result = match purpose.as_str() {
        PURPOSE_PERIOD_FEE => mark_period_fee_paid(state, &mut tx, id, user_id).await,
        PURPOSE_LATE_CANCEL => mark_late_cancel_compensation_paid(&mut tx, user_id).await,
        PURPOSE_RENTAL_ADVANCE => {
            apply_rental_advance(&mut tx, user_id, meta.as_ref(), payment_id).await
        }
        PURPOSE_RENTAL_SETTLEMENT => {
            apply_rental_settlement(&mut tx, user_id, meta.as_ref(), payment_id).await
        }
        _ => Err(AppError::Conflict(
            "Payment purpose requires reconciliation".into(),
        )),
    };
    match apply_result {
        Ok(()) => {
            sqlx::query(
                r#"UPDATE payment_orders SET status='CREDITED', "razorpayPaymentId"=$2, "updatedAt"=NOW() WHERE id=$1"#,
            )
            .bind(id)
            .bind(payment_id)
            .execute(&mut *tx)
            .await?;
            tx.commit().await?;
            Ok(())
        }
        Err(AppError::Conflict(msg)) if msg == "RENTAL_ADVANCE_REFUND_REQUIRED" => {
            sqlx::query(
                r#"UPDATE payment_orders
                   SET status='REFUND_REQUIRED'::payment_orders_status_enum,
                       "razorpayPaymentId"=$2, "updatedAt"=NOW()
                   WHERE id=$1"#,
            )
            .bind(id)
            .bind(payment_id)
            .execute(&mut *tx)
            .await?;
            enqueue_refund_required(&mut tx, id, order_id, payment).await?;
            // Notify renter (payout-independent refund status).
            crate::outbox::notify(
                &mut tx,
                id,
                user_id,
                "Rental advance refund pending",
                "Your advance was captured after the hold expired. A refund has been queued.",
                json!({
                    "type": "rental_refund_required",
                    "paymentOrderId": id,
                    "reservationId": meta.as_ref().and_then(|m| m.get("reservationId")).cloned(),
                    "refundStatus": "REFUND_REQUIRED",
                }),
            )
            .await?;
            tx.commit().await?;
            Ok(())
        }
        Err(e) => Err(e),
    }
}

async fn enqueue_refund_required(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    payment_order_id: Uuid,
    order_id: &str,
    payment: &Value,
) -> AppResult<()> {
    // Separate outbox id — payment.captured already owns payment_orders.id.
    let already: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
               SELECT 1 FROM outbox_events
               WHERE type='payment.refund_required' AND "aggregateId"=$1
                 AND status IN ('pending','processing')
           )"#,
    )
    .bind(payment_order_id)
    .fetch_one(&mut **tx)
    .await?;
    if already {
        return Ok(());
    }
    sqlx::query(
        r#"INSERT INTO outbox_events (id, type, "aggregateId", payload)
           VALUES ($1, 'payment.refund_required', $2, $3)"#,
    )
    .bind(Uuid::new_v4())
    .bind(payment_order_id)
    .bind(json!({
        "orderId": order_id,
        "paymentOrderId": payment_order_id,
        "payment": {
            "id": payment["id"],
            "order_id": payment.get("order_id").cloned().unwrap_or(json!(order_id)),
            "amount": payment["amount"],
            "currency": payment["currency"],
        }
    }))
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub(crate) async fn process_refund_required(state: &AppState, payload: &Value) -> AppResult<()> {
    let payment_order_id = payload
        .get("paymentOrderId")
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("Missing paymentOrderId".into()))?;
    let pid = Uuid::parse_str(payment_order_id)?;
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, amount, "razorpayPaymentId", meta, "userId"
           FROM payment_orders WHERE id=$1 FOR UPDATE"#,
    )
    .bind(pid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Payment order not found".into()))?;
    let status = row.get::<String, _>("status");
    if status == "REFUNDED" {
        return Ok(());
    }
    if status != "REFUND_REQUIRED" && status != "REFUND_PENDING" {
        return Err(AppError::Conflict(
            "Payment order is not awaiting refund".into(),
        ));
    }
    let payment_id = row
        .get::<Option<String>, _>("razorpayPaymentId")
        .or_else(|| {
            payload
                .pointer("/payment/id")
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .ok_or_else(|| AppError::BadRequest("Missing captured payment id for refund".into()))?;
    let amount = rust_decimal::prelude::ToPrimitive::to_i32(
        &row.get::<rust_decimal::Decimal, _>("amount"),
    )
    .unwrap_or(0);
    let reservation_id = row
        .get::<Option<Value>, _>("meta")
        .as_ref()
        .and_then(|m| m.get("reservationId"))
        .and_then(Value::as_str)
        .unwrap_or(payment_order_id)
        .to_string();

    sqlx::query(
        r#"UPDATE payment_orders
           SET status='REFUND_PENDING'::payment_orders_status_enum,
               "refundFailure"=NULL, "updatedAt"=NOW()
           WHERE id=$1"#,
    )
    .bind(pid)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    match refund_payment(
        state,
        &payment_id,
        amount,
        &format!("gixbee-rental-{reservation_id}-{payment_id}"),
    )
    .await
    {
        Ok(()) => {
            sqlx::query(
                r#"UPDATE payment_orders
                   SET status='REFUNDED'::payment_orders_status_enum,
                       "refundedAt"=NOW(), "refundFailure"=NULL, "updatedAt"=NOW()
                   WHERE id=$1"#,
            )
            .bind(pid)
            .execute(&state.db)
            .await?;
            if let Ok(rid) = Uuid::parse_str(&reservation_id) {
                let _ = sqlx::query(
                    r#"UPDATE rental_reservations
                       SET "priceBreakdown" = jsonb_set(
                           COALESCE("priceBreakdown", '{}'::jsonb),
                           '{refundStatus}', '"REFUNDED"'::jsonb, true),
                           "updatedAt"=NOW()
                       WHERE id=$1"#,
                )
                .bind(rid)
                .execute(&state.db)
                .await;
            }
            Ok(())
        }
        Err(e) => {
            let detail = e.to_string();
            sqlx::query(
                r#"UPDATE payment_orders
                   SET status='REFUND_REQUIRED'::payment_orders_status_enum,
                       "refundFailure"=$2, "updatedAt"=NOW()
                   WHERE id=$1"#,
            )
            .bind(pid)
            .bind(&detail)
            .execute(&state.db)
            .await?;
            Err(e)
        }
    }
}

async fn apply_rental_advance(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    uid: Uuid,
    meta: Option<&Value>,
    razorpay_payment_id: &str,
) -> AppResult<()> {
    let reservation_id = meta
        .and_then(|m| m.get("reservationId"))
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("Rental payment is missing its booking".into()))?;
    let rid = Uuid::parse_str(reservation_id)?;
    let reservation = sqlx::query(
        r#"SELECT status::text AS status, "priceBreakdown"->>'razorpayPaymentId' AS "capture",
                  "lateCapturePaymentId"
           FROM rental_reservations WHERE id=$1 AND "renterId"=$2 FOR UPDATE"#,
    )
    .bind(rid)
    .bind(uid)
    .fetch_optional(&mut **tx)
    .await?;
    let Some(reservation) = reservation else {
        return Err(AppError::NotFound("Reservation not found".into()));
    };
    if reservation.get::<Option<String>, _>("capture").as_deref() == Some(razorpay_payment_id)
        || reservation
            .get::<Option<String>, _>("lateCapturePaymentId")
            .as_deref()
            == Some(razorpay_payment_id)
    {
        return Ok(());
    }
    if !matches!(
        reservation.get::<String, _>("status").as_str(),
        "TEMP_HOLD" | "PAYMENT_PENDING"
    ) {
        // Hold expired / cancelled — keep inventory free and mark capture for refund.
        sqlx::query(
            r#"UPDATE rental_reservations
               SET "lateCapturePaymentId" = $3,
                   "priceBreakdown" = jsonb_set(
                       jsonb_set(COALESCE("priceBreakdown", '{}'::jsonb), '{lateCapturePaymentId}', to_jsonb($3::text), true),
                       '{refundStatus}', '"REFUND_REQUIRED"'::jsonb, true),
                   "updatedAt" = NOW()
               WHERE id = $1 AND "renterId" = $2"#,
        )
        .bind(rid)
        .bind(uid)
        .bind(razorpay_payment_id)
        .execute(&mut **tx)
        .await?;
        return Err(AppError::Conflict(
            "RENTAL_ADVANCE_REFUND_REQUIRED".into(),
        ));
    }
    sqlx::query(
        r#"UPDATE rental_reservations
           SET status = 'PENDING_OWNER_CONFIRMATION'::rental_reservations_status_enum,
               "paymentStatus" = 'ADVANCE_PAID',
               "holdExpiresAt" = NULL,
               "priceBreakdown" = jsonb_set(COALESCE("priceBreakdown", '{}'::jsonb), '{razorpayPaymentId}', to_jsonb($3::text), true),
               "updatedAt" = NOW()
           WHERE id = $1 AND "renterId" = $2"#,
    )
    .bind(rid)
    .bind(uid)
    .bind(razorpay_payment_id)
    .execute(&mut **tx)
    .await?;
    let owner: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT i."ownerId" FROM rental_items i JOIN rental_reservations r ON r."itemId"=i.id WHERE r.id=$1"#,
    )
    .bind(rid)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(owner) = owner {
        crate::outbox::notify(
            tx,
            rid,
            owner,
            "New rental request",
            "Advance paid. Confirm or reject this rental request.",
            json!({"type":"rental_request","reservationId":rid,"audience":"owner"}),
        )
        .await?;
    }
    Ok(())
}

async fn apply_rental_settlement(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    uid: Uuid,
    meta: Option<&Value>,
    razorpay_payment_id: &str,
) -> AppResult<()> {
    let reservation_id = meta
        .and_then(|m| m.get("reservationId"))
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("Rental payment is missing its booking".into()))?;
    let rid = Uuid::parse_str(reservation_id)?;
    let change = sqlx::query(
        r#"UPDATE rental_reservations
           SET "paymentStatus" = 'SETTLED',
               "remainingAmount" = 0,
               "renterPaidAt" = COALESCE("renterPaidAt", NOW()),
               "ownerPaidAt" = COALESCE("ownerPaidAt", NOW()),
               "priceBreakdown" = jsonb_set(COALESCE("priceBreakdown", '{}'::jsonb), '{settlementPaymentId}', to_jsonb($3::text), true),
               "updatedAt" = NOW()
           WHERE id = $1 AND "renterId" = $2 AND status::text IN ('ACTIVE','RETURN_PENDING')
             AND "paymentStatus"::text IS DISTINCT FROM 'SETTLED'"#,
    )
    .bind(rid)
    .bind(uid)
    .bind(razorpay_payment_id)
    .execute(&mut **tx)
    .await?;
    if change.rows_affected() == 0 {
        let already_applied: bool = sqlx::query_scalar(
            r#"SELECT EXISTS(SELECT 1 FROM rental_reservations
               WHERE id=$1 AND "renterId"=$2 AND "priceBreakdown"->>'settlementPaymentId'=$3)"#,
        ).bind(rid).bind(uid).bind(razorpay_payment_id).fetch_one(&mut **tx).await?;
        if already_applied {
            return Ok(());
        }
        return Err(AppError::Conflict("Captured rental settlement requires reconciliation".into()));
    }
    sqlx::query(
        r#"UPDATE rental_reservations SET status = 'COMPLETED'::rental_reservations_status_enum
           WHERE id = $1 AND status::text = 'RETURN_PENDING'
             AND "ownerReturnedAt" IS NOT NULL AND "renterReturnedAt" IS NOT NULL"#,
    )
    .bind(rid)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn fulfil_order(
    state: &AppState,
    razorpay_order_id: &str,
    user_id: &str,
    amount_inr: i32,
    purpose: &str,
    meta: Option<&Value>,
    payment_order_id: Uuid,
    razorpay_payment_id: Option<&str>,
) -> AppResult<()> {
    match purpose {
        crate::plans::PURPOSE => {
            crate::plans::fulfil(state, user_id, payment_order_id, meta.unwrap_or(&Value::Null)).await?;
        }
        PURPOSE_HIRING_MATCH => {
            create_request_from_payment(
                state,
                user_id,
                meta.unwrap_or(&json!({})),
                payment_order_id,
                razorpay_payment_id,
            )
            .await?;
            info!(
                "[Razorpay] {}: hiring match fee ₹{} — request started for {}",
                razorpay_order_id,
                amount_inr,
                user_id
            );
        }
        PURPOSE_EXTRA_JOB_TYPE => {
            create_preference_from_payment(state, user_id, meta.unwrap_or(&json!({})),payment_order_id).await?;
            info!(
                "[Razorpay] {}: extra Job Type fee ₹{} — preference created for {}",
                razorpay_order_id,
                amount_inr,
                user_id
            );
        }
        other => {
            warn!(
                "[Razorpay] {}: unknown purpose {:?} — no fulfilment",
                razorpay_order_id,
                other
            );
        }
    }
    Ok(())
}

pub async fn refund_hiring_match_payment(
    state: &AppState,
    razorpay_payment_id: &str,
    amount_inr: i32,
    request_id: &str,
) -> AppResult<()> {
    refund_payment(
        state,
        razorpay_payment_id,
        amount_inr,
        &format!("gixbee-hiring-{request_id}"),
    )
    .await
}

async fn refund_payment(
    state: &AppState,
    razorpay_payment_id: &str,
    amount_inr: i32,
    idempotency_key: &str,
) -> AppResult<()> {
    if amount_inr <= 0 {
        return Ok(());
    }
    if !razorpay_configured(state) {
        return Err(AppError::BadRequest(
            "Cannot refund — payment gateway is not configured.".into(),
        ));
    }
    let key_id = state.config.razorpay_key_id.as_deref().unwrap_or("");
    let key_secret = state.config.razorpay_key_secret.as_deref().unwrap_or("");
    let auth = STANDARD.encode(format!("{}:{}", key_id, key_secret));
    let paise = amount_inr * 100;
    let res = state
        .http
        .post(format!(
            "https://api.razorpay.com/v1/payments/{}/refund",
            razorpay_payment_id
        ))
        .header("Authorization", format!("Basic {}", auth))
        .header("X-Refund-Idempotency", idempotency_key)
        .timeout(std::time::Duration::from_secs(20))
        .json(&json!({ "amount": paise, "speed":"normal" }))
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("Razorpay refund failed: {}", e)))?;

    if !res.status().is_success() {
        let status = res.status();
        let detail = res.text().await.unwrap_or_default();
        // Already-refunded is treated as success for crash/retry safety.
        if status.as_u16() == 400
            && detail.to_lowercase().contains("already")
        {
            info!(
                "[Razorpay] refund already recorded for payment {}",
                razorpay_payment_id
            );
            return Ok(());
        }
        error!(
            "[Razorpay] refund failed ({}): {}",
            status,
            detail.chars().take(500).collect::<String>()
        );
        return Err(AppError::BadRequest(
            "Refund could not be processed automatically — support will complete it.".into(),
        ));
    }
    info!(
        "[Razorpay] refunded ₹{} on payment {}",
        amount_inr, razorpay_payment_id
    );
    Ok(())
}

async fn apply_first_recharge_bonus(state: &AppState, user_id: &str) {
    let uid = match Uuid::parse_str(user_id) {
        Ok(u) => u,
        Err(_) => return,
    };
    let credited_count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*)::bigint FROM payment_orders
           WHERE "userId" = $1 AND status = 'CREDITED' AND purpose::text = $2"#,
    )
    .bind(uid)
    .bind(PURPOSE_WALLET_RECHARGE)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten()
    .unwrap_or(0);

    if credited_count != 1 {
        return;
    }

    let bonus = config_number(state, "first_recharge_bonus", 0).await;
    if bonus <= 0 {
        return;
    }

    if let Err(e) = add_funds(state, user_id, bonus, "First recharge bonus").await {
        warn!(
            "[Razorpay] first-recharge bonus failed for {}: {}",
            user_id,
            e
        );
    } else {
        info!("[Razorpay] first-recharge bonus ₹{} → {}", bonus, user_id);
    }
}
