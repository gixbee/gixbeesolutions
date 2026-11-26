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
use crate::middleware::auth::AuthUser;
use crate::state::AppState;
use crate::wallets::add_funds;
use crate::workers::{mark_period_fee_paid, periodic_jobs_per_payment};

type HmacSha256 = Hmac<Sha256>;
mod recovery;

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
        .route("/webhook", post(webhook))
}

fn razorpay_configured(state: &AppState) -> bool {
    is_real_secret(state.config.razorpay_key_id.as_deref())
        && is_real_secret(state.config.razorpay_key_secret.as_deref())
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
    let receipt = format!("{}_{}", receipt_prefix, Uuid::new_v4().simple());

    let uid = Uuid::parse_str(user_id)?;
    let hiring_basic = if purpose == PURPOSE_HIRING_MATCH {
        Some(crate::master_admin::plan_value(&state.db, "hiring_basic_limit").await?)
    } else { None };
    let mut tx = state.db.begin().await?;
    if [PURPOSE_HIRING_MATCH,PURPOSE_EXTRA_JOB_TYPE,crate::plans::PURPOSE].contains(&purpose) {
        sqlx::query("SELECT id FROM users WHERE id=$1 FOR UPDATE").bind(uid).fetch_one(&mut *tx).await?;
        let existing=sqlx::query(r#"SELECT "razorpayOrderId",amount,meta FROM payment_orders WHERE "userId"=$1
            AND purpose::text=$2 AND status='CREATED' AND (meta-'fee'-'creditApplied'-'durationDays')=($3::jsonb-'fee'-'creditApplied'-'durationDays')
            AND ($2 <> 'PLATFORM_PLAN' OR amount=$4)
            ORDER BY "createdAt" DESC LIMIT 1"#).bind(uid).bind(purpose).bind(&meta).bind(rupees).fetch_optional(&mut *tx).await?;
        if let Some(existing)=existing {
            let due=existing.get::<rust_decimal::Decimal,_>("amount");let saved:Value=existing.get("meta");
            return Ok(Json(json!({"orderId":existing.get::<String,_>("razorpayOrderId"),
                "amount":rust_decimal::prelude::ToPrimitive::to_i64(&(due*rust_decimal::Decimal::from(100))),
                "amountDue":rust_decimal::prelude::ToPrimitive::to_i32(&due),"creditApplied":saved["creditApplied"],
                "currency":"INR","keyId":key_id,"resumed":true})));
        }
    }
    if let Some(basic) = hiring_basic {
        let business = meta.as_ref().and_then(|m|m["businessId"].as_str())
            .ok_or_else(|| AppError::BadRequest("Hiring business is required".into()))?;
        crate::plans::check_hiring_limit(&mut tx, uid, Uuid::parse_str(business)?, basic).await?;
        let balance: rust_decimal::Decimal = sqlx::query_scalar(r#"SELECT "hiringCreditBalance" FROM users WHERE id=$1 FOR UPDATE"#)
            .bind(uid).fetch_one(&mut *tx).await?;
        let reserved = crate::matching::reserved_hiring_credit(&mut *tx, uid, None).await?;
        let applied = meta.as_ref().and_then(|v|v.get("creditApplied")).and_then(Value::as_i64).unwrap_or(0);
        if balance - reserved < rust_decimal::Decimal::from(applied) {
            return Err(AppError::Conflict("Hiring credit changed. Refresh the payment quote.".into()));
        }
    }

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
            "notes": { "gixbeeUserId": user_id, "purpose": purpose },
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
        .ok_or_else(|| AppError::Internal("Razorpay order id missing".into()))?;

    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO payment_orders (id, "userId", purpose, amount, status, "razorpayOrderId", meta)
           VALUES ($1, $2, $3::payment_orders_purpose_enum, $4, 'CREATED', $5, $6)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(purpose)
    .bind(rupees)
    .bind(razorpay_order_id)
    .bind(meta)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    info!(
        "[Razorpay] order {} created — ₹{} {} for {}",
        razorpay_order_id,
        rupees,
        purpose,
        user_id
    );

    Ok(Json(json!({
        "orderId": razorpay_order_id,
        "amount": rupees * 100,
        "currency": "INR",
        "keyId": key_id,
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

    let claim = sqlx::query(
        r#"UPDATE payment_orders
           SET status = 'CREDITED', "razorpayPaymentId" = $2
           WHERE "razorpayOrderId" = $1 AND status = 'CREATED' AND purpose::text != 'JOB_CREDITS'"#,
    )
    .bind(order_id)
    .bind(payment_id)
    .execute(&state.db)
    .await?;

    if claim.rows_affected() == 0 {
        info!(
            "[Razorpay] {}: already credited or unknown — duplicate delivery ignored",
            order_id
        );
        return Ok(Json(json!({ "ok": true, "duplicate": true })));
    }

    let row = sqlx::query(
        r#"SELECT id, "userId", amount, purpose::text AS purpose, meta, "razorpayPaymentId"
           FROM payment_orders WHERE "razorpayOrderId" = $1"#,
    )
    .bind(order_id)
    .fetch_one(&state.db)
    .await?;

    let order_uuid = row.get::<Uuid, _>("id");
    let user_id = row.get::<Uuid, _>("userId").to_string();
    let amount = row
        .try_get::<rust_decimal::Decimal, _>("amount")
        .ok()
        .and_then(|d| d.round().to_string().parse::<i32>().ok())
        .unwrap_or(0);
    let purpose = row.get::<String, _>("purpose");
    let meta = row.get::<Option<Value>, _>("meta");
    let razorpay_payment_id = row.get::<Option<String>, _>("razorpayPaymentId");

    let fulfil = fulfil_order(
        &state,
        order_id,
        &user_id,
        amount,
        &purpose,
        meta.as_ref(),
        order_uuid,
        razorpay_payment_id.as_deref(),
    )
    .await;

    if let Err(e) = fulfil {
        let _ = sqlx::query(
            r#"UPDATE payment_orders
               SET status = 'CREATED', "razorpayPaymentId" = NULL
               WHERE "razorpayOrderId" = $1"#,
        )
        .bind(order_id)
        .execute(&state.db)
        .await;
        error!(
            "[Razorpay] {}: fulfilment FAILED — claim reverted for retry: {}",
            order_id,
            e
        );
        return Err(e);
    }

    Ok(Json(json!({ "ok": true })))
}

async fn apply_rental_advance(
    state: &AppState,
    user_id: &str,
    meta: Option<&Value>,
    razorpay_payment_id: Option<&str>,
) -> AppResult<()> {
    let reservation_id = meta
        .and_then(|m| m.get("reservationId"))
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("Rental payment is missing its booking".into()))?;
    let rid = Uuid::parse_str(reservation_id)?;
    let uid = Uuid::parse_str(user_id)?;
    let mut tx = state.db.begin().await?;
    let status: Option<String> = sqlx::query_scalar(
        r#"SELECT status::text FROM rental_reservations WHERE id=$1 AND "renterId"=$2 FOR UPDATE"#,
    )
    .bind(rid)
    .bind(uid)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(status) = status else {
        return Err(AppError::NotFound("Reservation not found".into()));
    };
    if !matches!(status.as_str(), "TEMP_HOLD" | "PAYMENT_PENDING") {
        tx.commit().await?;
        return Ok(());
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
    .bind(razorpay_payment_id.unwrap_or(""))
    .execute(&mut *tx)
    .await?;
    let owner: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT i."ownerId" FROM rental_items i JOIN rental_reservations r ON r."itemId"=i.id WHERE r.id=$1"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(owner) = owner {
        crate::outbox::notify(
            &mut tx,
            rid,
            owner,
            "New rental request",
            "Advance paid. Confirm or reject this rental request.",
            json!({"type":"rental_request","reservationId":rid,"audience":"owner"}),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

async fn apply_rental_settlement(
    state: &AppState,
    user_id: &str,
    meta: Option<&Value>,
    razorpay_payment_id: Option<&str>,
) -> AppResult<()> {
    let reservation_id = meta
        .and_then(|m| m.get("reservationId"))
        .and_then(Value::as_str)
        .ok_or_else(|| AppError::BadRequest("Rental payment is missing its booking".into()))?;
    let rid = Uuid::parse_str(reservation_id)?;
    let uid = Uuid::parse_str(user_id)?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE rental_reservations
           SET "paymentStatus" = 'SETTLED',
               "remainingAmount" = 0,
               "renterPaidAt" = COALESCE("renterPaidAt", NOW()),
               "ownerPaidAt" = COALESCE("ownerPaidAt", NOW()),
               "priceBreakdown" = jsonb_set(COALESCE("priceBreakdown", '{}'::jsonb), '{settlementPaymentId}', to_jsonb($3::text), true),
               "updatedAt" = NOW()
           WHERE id = $1 AND "renterId" = $2 AND status::text IN ('ACTIVE','RETURN_PENDING')"#,
    )
    .bind(rid)
    .bind(uid)
    .bind(razorpay_payment_id.unwrap_or(""))
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"UPDATE rental_reservations SET status = 'COMPLETED'::rental_reservations_status_enum
           WHERE id = $1 AND status::text = 'RETURN_PENDING'
             AND "ownerReturnedAt" IS NOT NULL AND "renterReturnedAt" IS NOT NULL"#,
    )
    .bind(rid)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
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
        PURPOSE_PERIOD_FEE => {
            mark_period_fee_paid(state, user_id).await?;
            info!(
                "[Razorpay] {}: period fee ₹{} — jobs unlocked for {}",
                razorpay_order_id,
                amount_inr,
                user_id
            );
        }
        PURPOSE_LATE_CANCEL => {
            mark_late_cancel_compensation_paid(state, user_id).await?;
            info!(
                "[Razorpay] {}: late-cancel compensation ₹{} — Instant Help unlocked for {}",
                razorpay_order_id,
                amount_inr,
                user_id
            );
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
        PURPOSE_WALLET_RECHARGE => {
            if !WALLET_PAYMENTS_ENABLED {
                warn!(
                    "[Razorpay] {}: wallet recharge ignored — WALLET_PAYMENTS_ENABLED=false",
                    razorpay_order_id
                );
                return Ok(());
            }
            add_funds(state, user_id, amount_inr, "Wallet Recharge (Razorpay)").await?;
            info!(
                "[Razorpay] {}: credited ₹{} to {}",
                razorpay_order_id,
                amount_inr,
                user_id
            );
            apply_first_recharge_bonus(state, user_id).await;
        }
        PURPOSE_RENTAL_ADVANCE => {
            apply_rental_advance(state, user_id, meta, razorpay_payment_id).await?;
            info!(
                "[Razorpay] {}: rental advance ₹{} for {}",
                razorpay_order_id, amount_inr, user_id
            );
        }
        PURPOSE_RENTAL_SETTLEMENT => {
            apply_rental_settlement(state, user_id, meta, razorpay_payment_id).await?;
            info!(
                "[Razorpay] {}: rental settlement ₹{} for {}",
                razorpay_order_id, amount_inr, user_id
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
        .header("X-Refund-Idempotency", format!("gixbee-hiring-{request_id}"))
        .timeout(std::time::Duration::from_secs(20))
        .json(&json!({ "amount": paise, "speed":"normal" }))
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("Razorpay refund failed: {}", e)))?;

    if !res.status().is_success() {
        let status = res.status();
        let detail = res.text().await.unwrap_or_default();
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
        amount_inr,
        razorpay_payment_id
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
