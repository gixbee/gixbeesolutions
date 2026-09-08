use chrono::{DateTime, Utc};
use rust_decimal::prelude::{FromPrimitive, ToPrimitive};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::{Postgres, Row, Transaction};
use uuid::Uuid;

use crate::common::money::WALLET_PAYMENTS_ENABLED;
use crate::error::{AppError, AppResult};
use crate::state::AppState;
use crate::workers;

const INSTANT_PETROL_PER_KM_DEFAULT: i32 = 10;
const PLATFORM_FEE: i32 = 12;

fn generate_otp() -> String {
    format!("{:04}", rand::random::<u16>() % 9000 + 1000)
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

pub async fn cache_and_emit_status(
    state: &AppState,
    booking_id: &str,
    status: &str,
    operator_id: Option<&str>,
    operator_name: Option<&str>,
    customer_id: Option<&str>,
    arrival_otp: Option<&str>,
    is_paid: Option<bool>,
    worker_paid_confirmed: Option<bool>,
    customer_paid_confirmed: Option<bool>,
) {
    let mut patch = json!({
        "status": status,
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": operator_id,
        "operatorName": operator_name,
        "customerId": customer_id,
    });
    if let Some(obj) = patch.as_object_mut() {
        if let Some(otp) = arrival_otp {
            obj.insert("arrivalOtp".into(), json!(otp));
        }
        if let Some(v) = is_paid {
            obj.insert("isPaid".into(), json!(v));
        }
        if let Some(v) = worker_paid_confirmed {
            obj.insert("workerPaidConfirmed".into(), json!(v));
        }
        if let Some(v) = customer_paid_confirmed {
            obj.insert("customerPaidConfirmed".into(), json!(v));
        }
    }
    let _ = state.redis.cache_booking_status(booking_id, &patch).await;
    if let Some(cid) = customer_id {
        let customer_payload = if status == "ACCEPTED" || status == "ARRIVED" {
            patch.clone()
        } else {
            let mut p = patch.clone();
            if let Some(obj) = p.as_object_mut() {
                obj.insert("arrivalOtp".into(), Value::Null);
            }
            p
        };
        state
            .realtime
            .emit_to_user(cid, "booking_status_update", &customer_payload)
            .await;
    }
    if let Some(oid) = operator_id {
        let mut worker_payload = patch.clone();
        if let Some(obj) = worker_payload.as_object_mut() {
            obj.insert("arrivalOtp".into(), Value::Null);
        }
        state
            .realtime
            .emit_to_user(oid, "booking_status_update", &worker_payload)
            .await;
    }
}

pub async fn verify_arrival_otp(
    state: &AppState,
    booking_id: &str,
    otp: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, "arrivalOtp", "customerId", "operatorId"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let expected = row.get::<Option<String>, _>("arrivalOtp");
    if expected.as_deref() != Some(otp) {
        return Err(AppError::BadRequest("Invalid arrival OTP".into()));
    }

    let status = row.get::<String, _>("status");
    if status != "ACCEPTED" && status != "ARRIVED" {
        return Err(AppError::BadRequest(
            "Arrival OTP can only be verified after the pro has accepted / arrived.".into(),
        ));
    }

    let _ = state
        .redis
        .del(&format!("otp:booking:{}:arrival", booking_id))
        .await;

    sqlx::query(
        r#"UPDATE bookings SET status = 'ACTIVE', "startedAt" = NOW() WHERE id = $1"#,
    )
    .bind(bid)
    .execute(&state.db)
    .await?;

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten()
        .map(|u| u.to_string());
    let operator_name: Option<String> = if let Some(op) = operator_id.as_ref() {
        sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
            .bind(Uuid::parse_str(op)?)
            .fetch_optional(&state.db)
            .await?
    } else {
        None
    };

    cache_and_emit_status(
        state,
        booking_id,
        "ACTIVE",
        operator_id.as_deref(),
        operator_name.as_deref(),
        Some(&customer_id),
        None,
        None,
        None,
        None,
    )
    .await;

    Ok(json!({
        "message": "Arrival confirmed. Job is now active.",
        "status": "ACTIVE",
    }))
}

pub async fn notify_arrival(
    state: &AppState,
    booking_id: &str,
    worker_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let wid = Uuid::parse_str(worker_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "arrivalOtp", "customerId", "operatorId"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() != Some(wid) {
        return Err(AppError::NotFound("Booking not found".into()));
    }

    let status = row.get::<String, _>("status");
    if status != "ACCEPTED" && status != "ARRIVED" {
        return Err(AppError::BadRequest(
            "Arrival can only be marked while the job is accepted.".into(),
        ));
    }

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let arrival_otp = row.get::<Option<String>, _>("arrivalOtp");

    if status == "ACCEPTED" {
        sqlx::query(r#"UPDATE bookings SET status = 'ARRIVED' WHERE id = $1"#)
            .bind(bid)
            .execute(&state.db)
            .await?;
        let operator_name: Option<String> = sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
            .bind(wid)
            .fetch_optional(&state.db)
            .await?;
        cache_and_emit_status(
            state,
            booking_id,
            "ARRIVED",
            Some(worker_id),
            operator_name.as_deref(),
            Some(&customer_id),
            arrival_otp.as_deref(),
            None,
            None,
            None,
        )
        .await;
    }

    if let Some(otp) = arrival_otp.as_deref() {
        state
            .fcm
            .send_to_user(
                state,
                &customer_id,
                "Worker has arrived",
                &format!("Arrival OTP: {}. Share this with the worker to begin.", otp),
                Some(&[
                    ("type", "booking_status_update"),
                    ("bookingId", booking_id),
                    ("status", "ARRIVED"),
                ]),
            )
            .await;
    }

    Ok(json!({
        "message": "Arrival OTP sent to customer.",
        "status": "ARRIVED",
    }))
}

pub async fn notify_completion(
    state: &AppState,
    booking_id: &str,
    worker_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let wid = Uuid::parse_str(worker_id)?;

    let row = sqlx::query(
        r#"SELECT "customerId", "operatorId", "completionOtp" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() != Some(wid) {
        return Err(AppError::NotFound("Booking not found".into()));
    }

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    if let Some(otp) = row.get::<Option<String>, _>("completionOtp") {
        state
            .fcm
            .send_to_user(
                state,
                &customer_id,
                "Job marked as complete",
                &format!(
                    "Completion OTP: {}. Enter this to confirm and close the job.",
                    otp
                ),
                None,
            )
            .await;
    }

    Ok(json!({ "message": "Completion OTP sent to customer." }))
}

pub async fn verify_completion_otp(
    state: &AppState,
    booking_id: &str,
    otp: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;

    let booking = sqlx::query(
        r#"SELECT status::text AS status, "completionOtp", type::text AS type, amount,
                  "acceptDistanceKm", "startedAt", "paymentMethod", "customerId", "operatorId",
                  "workerPaidConfirmed", "customerPaidConfirmed", "isPaid"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let expected = booking.get::<Option<String>, _>("completionOtp");
    if expected.as_deref() != Some(otp) {
        return Err(AppError::BadRequest("Invalid completion OTP".into()));
    }

    if booking.get::<String, _>("status") != "ACTIVE" {
        return Err(AppError::BadRequest("Job must be active to complete".into()));
    }

    let _ = state
        .redis
        .del(&format!("otp:booking:{}:completion", booking_id))
        .await;

    let booking_type = booking.get::<String, _>("type");
    let configured_petrol_rate = if booking_type == "INSTANT" {
        config_number(state, "instant_petrol_per_km", INSTANT_PETROL_PER_KM_DEFAULT).await
    } else {
        0
    };

    let mut tx = state.db.begin().await?;

    let claim = sqlx::query(
        r#"UPDATE bookings SET status = 'COMPLETED', "completedAt" = NOW()
           WHERE id = $1 AND status = 'ACTIVE'"#,
    )
    .bind(bid)
    .execute(&mut tx)
    .await?;

    if claim.rows_affected() == 0 {
        tx.rollback().await?;
        return Err(AppError::BadRequest("Job must be active to complete".into()));
    }

    let locked = sqlx::query(
        r#"SELECT type::text AS type, amount, "acceptDistanceKm", "startedAt", "paymentMethod",
                  "customerId", "operatorId", "workerPaidConfirmed", "customerPaidConfirmed", "isPaid"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_one(&mut tx)
    .await?;

    let started_at: Option<DateTime<Utc>> = locked
        .try_get::<Option<DateTime<Utc>>, _>("startedAt")
        .ok()
        .flatten();
    let start_ms = started_at
        .map(|t| t.timestamp_millis())
        .unwrap_or_else(|| Utc::now().timestamp_millis());
    let elapsed_ms = (Utc::now().timestamp_millis() - start_ms).max(0);
    let worked_minutes = ((elapsed_ms as f64) / 60000.0).round().max(1.0) as i32;
    let billing_hours = ((worked_minutes as f64) / 60.0).ceil().max(1.0) as i32;

    let hourly_rate = locked
        .try_get::<Option<rust_decimal::Decimal>, _>("amount")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let billable_minutes = worked_minutes.max(60);
    let service_amount = if booking_type == "INSTANT" {
        (hourly_rate * (billable_minutes as f64 / 60.0)).round() as i32
    } else {
        hourly_rate.round() as i32
    };

    let raw_petrol_distance = locked
        .try_get::<Option<rust_decimal::Decimal>, _>("acceptDistanceKm")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64());
    let petrol_distance_km = if booking_type == "INSTANT" {
        raw_petrol_distance
            .filter(|d| d.is_finite() && *d > 0.0)
            .unwrap_or(0.0)
    } else {
        0.0
    };
    let petrol_rate_per_km = if booking_type == "INSTANT" {
        configured_petrol_rate
    } else {
        0
    };
    let petrol_amount = if booking_type == "INSTANT" {
        (petrol_distance_km * petrol_rate_per_km as f64).round() as i32
    } else {
        0
    };
    let total_amount = service_amount + petrol_amount;

    let petrol_distance_dec = Decimal::from_f64_retain(petrol_distance_km)
        .unwrap_or(Decimal::ZERO);
    let petrol_rate_dec =
        Decimal::from_i32(petrol_rate_per_km).unwrap_or(Decimal::ZERO);
    let total_dec = Decimal::from_i32(total_amount).unwrap_or(Decimal::ZERO);

    let payment_method = locked
        .get::<Option<String>, _>("paymentMethod")
        .unwrap_or_else(|| "CASH".to_string());
    let mut is_paid = locked.get::<bool, _>("isPaid");

    if booking_type == "INSTANT" {
        is_paid = false;
    } else if WALLET_PAYMENTS_ENABLED && payment_method == "WALLET" && total_amount <= 0 {
        is_paid = true;
    }

    let worker_paid_confirmed = locked.get::<bool, _>("workerPaidConfirmed");
    let customer_paid_confirmed = locked.get::<bool, _>("customerPaidConfirmed");

    sqlx::query(
        r#"UPDATE bookings SET
            "billingHours" = $1,
            "workedMinutes" = $2,
            "petrolDistanceKm" = $3,
            "petrolRatePerKm" = $4,
            "petrolAmount" = $5,
            "totalAmount" = $6,
            "isPaid" = $7
           WHERE id = $8"#,
    )
    .bind(billing_hours)
    .bind(worked_minutes)
    .bind(if booking_type == "INSTANT" {
        Some(petrol_distance_dec)
    } else {
        None
    })
    .bind(if booking_type == "INSTANT" {
        Some(petrol_rate_dec)
    } else {
        None
    })
    .bind(if booking_type == "INSTANT" {
        Some(petrol_amount)
    } else {
        None
    })
    .bind(total_dec)
    .bind(is_paid)
    .bind(bid)
    .execute(&mut tx)
    .await?;

    let customer_id = locked.get::<Uuid, _>("customerId");
    let operator_id = locked
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();
    let operator_name: Option<String> = if let Some(op) = operator_id {
        sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
            .bind(op)
            .fetch_optional(&mut tx)
            .await?
    } else {
        None
    };
    let customer_name: Option<String> = sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
        .bind(customer_id)
        .fetch_optional(&mut tx)
        .await?;

    let outbox_payload = json!({
        "bookingId": booking_id,
        "customerId": customer_id.to_string(),
        "operatorId": operator_id.map(|u| u.to_string()),
        "operatorName": operator_name,
        "isPaid": is_paid,
        "workerPaidConfirmed": worker_paid_confirmed,
        "customerPaidConfirmed": customer_paid_confirmed,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts)
           VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.completed")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&mut tx)
    .await?;

    if let Some(op) = operator_id {
        mark_first_job_done(&mut tx, op).await?;
    }

    tx.commit().await?;

    cache_and_emit_status(
        state,
        booking_id,
        "COMPLETED",
        operator_id.map(|u| u.to_string()).as_deref(),
        operator_name.as_deref(),
        Some(&customer_id.to_string()),
        None,
        Some(is_paid),
        Some(worker_paid_confirmed),
        Some(customer_paid_confirmed),
    )
    .await;

    if let Some(op) = operator_id {
        workers::set_worker_status(state, &op.to_string(), "available").await;
    }

    Ok(json!({
        "message": "Job completed successfully.",
        "status": "COMPLETED",
        "billingHours": billing_hours,
        "workedMinutes": worked_minutes,
        "hourlyRate": hourly_rate,
        "serviceAmount": service_amount,
        "petrolDistanceKm": petrol_distance_km,
        "petrolRatePerKm": petrol_rate_per_km,
        "petrolAmount": petrol_amount,
        "platformFee": PLATFORM_FEE,
        "paymentMethod": payment_method,
        "totalAmount": total_amount,
        "isPaid": is_paid,
        "needsManualPayment": !is_paid,
        "customerName": customer_name,
        "workerName": operator_name,
    }))
}

async fn mark_first_job_done(
    tx: &mut Transaction<'_, Postgres>,
    operator_id: Uuid,
) -> AppResult<()> {
    let is_done: bool = sqlx::query_scalar(
        r#"SELECT "isFirstJobDone" FROM worker_profiles WHERE "userId" = $1"#,
    )
    .bind(operator_id)
    .fetch_optional(&mut tx)
    .await?
    .unwrap_or(false);
    if !is_done {
        sqlx::query(
            r#"UPDATE worker_profiles SET "isFirstJobDone" = true WHERE "userId" = $1"#,
        )
        .bind(operator_id)
        .execute(&mut tx)
        .await?;
    }
    Ok(())
}

pub async fn refresh_completion_otp(
    state: &AppState,
    booking_id: &str,
    customer_user_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let uid = Uuid::parse_str(customer_user_id)?;

    let row = sqlx::query(
        r#"SELECT "customerId", "completionOtp" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.get::<Uuid, _>("customerId") != uid {
        return Err(AppError::BadRequest(
            "Only the customer may refresh the completion OTP".into(),
        ));
    }

    let new_otp = generate_otp();
    sqlx::query(r#"UPDATE bookings SET "completionOtp" = $1 WHERE id = $2"#)
        .bind(&new_otp)
        .bind(bid)
        .execute(&state.db)
        .await?;

    let _ = state
        .redis
        .save_otp(&format!("otp:booking:{}:completion", booking_id), &new_otp)
        .await;

    state
        .fcm
        .send_to_user(
            state,
            customer_user_id,
            "Completion OTP refreshed",
            &format!("Completion OTP: {}. Enter this to confirm and close the job.", new_otp),
            None,
        )
        .await;

    Ok(json!({ "message": "Completion OTP refreshed" }))
}
