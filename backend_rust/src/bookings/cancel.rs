use chrono::{DateTime, Utc};
use rust_decimal::prelude::ToPrimitive;
use serde_json::{json, Value};
use sqlx::{Postgres, Row, Transaction};
use uuid::Uuid;

use crate::billing::refund_credit;
use crate::common::pg::timestamp_utc;
use crate::error::{AppError, AppResult};
use crate::redis::OPTIONAL_REDIS_TIMEOUT;
use crate::state::AppState;
use crate::workers;

const CANCEL_GRACE_MINUTES: i64 = 3;
const LATE_CANCEL_STRIKE_THRESHOLD: i32 = 3;
const COMP_PER_KM_DEFAULT: i32 = 10;
const COMP_MIN_INR_DEFAULT: i32 = 49;
const COMP_MAX_INR_DEFAULT: i32 = 299;

pub struct CancelOptions {
    pub apply_late_cancel_strike: bool,
    pub skip_stage_gate: bool,
    pub refund_job_credit: bool,
}

impl Default for CancelOptions {
    fn default() -> Self {
        Self {
            apply_late_cancel_strike: true,
            skip_stage_gate: false,
            refund_job_credit: true,
        }
    }
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

fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let r = 6371.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lng = (lng2 - lng1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    r * c
}

fn is_within_cancel_grace(accepted_at: Option<DateTime<Utc>>) -> bool {
    match accepted_at {
        None => true,
        Some(at) => {
            let grace = chrono::Duration::minutes(CANCEL_GRACE_MINUTES);
            Utc::now() - at <= grace
        }
    }
}

fn matching_status(status: &str) -> bool {
    matches!(status, "REQUESTED" | "PENDING" | "CUSTOM_REQUESTED")
}

pub async fn assert_participant(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
) -> AppResult<()> {
    let bid = Uuid::parse_str(booking_id)?;
    let uid = Uuid::parse_str(user_id)?;
    let row = sqlx::query(
        r#"SELECT "customerId", "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    let customer_id = row.get::<Uuid, _>("customerId");
    let operator_id = row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
    if customer_id != uid && operator_id != Some(uid) {
        return Err(AppError::Forbidden("Not a participant of this booking".into()));
    }
    Ok(())
}

pub async fn cache_and_emit_status(
    state: &AppState,
    booking_id: &str,
    status: &str,
    operator_id: Option<&str>,
    operator_name: Option<&str>,
    customer_id: Option<&str>,
    cancel_requested: bool,
) {
    let patch = json!({
        "status": status,
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": operator_id,
        "operatorName": operator_name,
        "customerId": customer_id,
        "cancelRequested": cancel_requested,
    });
    let _ = tokio::time::timeout(OPTIONAL_REDIS_TIMEOUT, async {
        tokio::join!(
            state.redis.cache_booking_status(booking_id, &patch),
            futures::future::join_all(
                [customer_id, operator_id]
                    .into_iter()
                    .flatten()
                    .map(|id| state.realtime.emit_to_user(id, "booking_status_update", &patch)),
            ),
        )
    })
    .await;
}

pub async fn publish_cancelled(
    state: &AppState,
    booking_id: &str,
    operator_id: Option<&str>,
    operator_name: Option<&str>,
    customer_id: Option<&str>,
) {
    cache_and_emit_status(
        state,
        booking_id,
        "CANCELLED",
        operator_id,
        operator_name,
        customer_id,
        false,
    )
    .await;
    if let Some(op) = operator_id {
        workers::set_worker_status(state, op, "available").await;
    }
}

struct Compensation {
    amount_inr: i32,
    distance_km: f64,
}

async fn compute_distance_compensation(
    state: &AppState,
    booking_id: Uuid,
    operator_id: Uuid,
    service_lat: Option<rust_decimal::Decimal>,
    service_lng: Option<rust_decimal::Decimal>,
) -> Compensation {
    let per_km = config_number(state, "late_cancel_compensation_per_km", COMP_PER_KM_DEFAULT).await;
    let min_inr = config_number(state, "late_cancel_compensation_min_inr", COMP_MIN_INR_DEFAULT).await;
    let max_inr = config_number(state, "late_cancel_compensation_max_inr", COMP_MAX_INR_DEFAULT).await;

    let job_lat = service_lat.and_then(|d| d.to_f64());
    let job_lng = service_lng.and_then(|d| d.to_f64());

    let worker_coords = if let Some(loc) =
        super::live_worker_location(state, &operator_id.to_string()).await
    {
        Some(loc)
    } else {
        sqlx::query(
            r#"SELECT "lastLat", "lastLng" FROM worker_profiles WHERE "userId" = $1"#,
        )
        .bind(operator_id)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten()
        .and_then(|r| {
            let la = r
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLat")
                .ok()
                .flatten()
                .and_then(|d| d.to_f64());
            let lo = r
                .try_get::<Option<rust_decimal::Decimal>, _>("lastLng")
                .ok()
                .flatten()
                .and_then(|d| d.to_f64());
            match (la, lo) {
                (Some(a), Some(b)) => Some((a, b)),
                _ => None,
            }
        })
    };

    let distance_km = match (job_lat, job_lng, worker_coords) {
        (Some(jlat), Some(jlng), Some((wlat, wlng))) => haversine_km(wlat, wlng, jlat, jlng),
        _ => 0.0,
    };

    let raw = (distance_km * per_km as f64).round() as i32;
    let amount_inr = raw.max(min_inr).min(max_inr);
    Compensation {
        amount_inr,
        distance_km: (distance_km * 100.0).round() / 100.0,
    }
}

async fn apply_late_cancel_strike(
    state: &AppState,
    tx: &mut Transaction<'_, Postgres>,
    customer_id: Uuid,
    booking_id: Uuid,
    operator_id: Option<Uuid>,
    service_lat: Option<rust_decimal::Decimal>,
    service_lng: Option<rust_decimal::Decimal>,
) -> AppResult<(i32, bool, Option<i32>, Option<f64>)> {
    let strike_count: i32 = sqlx::query_scalar(
        r#"SELECT "lateCancelStrikeCount" FROM users WHERE id = $1 FOR UPDATE"#,
    )
    .bind(customer_id)
    .fetch_optional(&mut **tx)
    .await?
    .unwrap_or(0);

    let new_strike = strike_count + 1;
    let mut instant_help_blocked = false;
    let mut compensation_amount = None;
    let mut compensation_distance = None;

    if new_strike >= LATE_CANCEL_STRIKE_THRESHOLD {
        if let Some(op) = operator_id {
            let comp = compute_distance_compensation(
                state,
                booking_id,
                op,
                service_lat,
                service_lng,
            )
            .await;
            instant_help_blocked = true;
            compensation_amount = Some(comp.amount_inr);
            compensation_distance = Some(comp.distance_km);

            sqlx::query(
                r#"UPDATE bookings SET
                    "lateCancelCompensationAmountInr" = $1,
                    "lateCancelCompensationDistanceKm" = $2
                   WHERE id = $3"#,
            )
            .bind(comp.amount_inr)
            .bind(comp.distance_km)
            .bind(booking_id)
            .execute(&mut **tx)
            .await?;

            sqlx::query(
                r#"UPDATE users SET
                    "lateCancelStrikeCount" = $1,
                    "instantHelpBlocked" = true,
                    "unblockCompensationBookingId" = $2,
                    "unblockCompensationAmountInr" = $3,
                    "unblockCompensationDistanceKm" = $4
                   WHERE id = $5"#,
            )
            .bind(new_strike)
            .bind(booking_id)
            .bind(comp.amount_inr)
            .bind(comp.distance_km)
            .bind(customer_id)
            .execute(&mut **tx)
            .await?;

            let bid_str = booking_id.to_string();
            state
                .fcm
                .send_to_user(
                    state,
                    &customer_id.to_string(),
                    "Instant Help blocked",
                    &format!(
                        "Pay ₹{} travel compensation to unlock Instant Help.",
                        comp.amount_inr
                    ),
                    Some(&[
                        ("type", "instant_help_blocked"),
                        ("bookingId", bid_str.as_str()),
                    ]),
                )
                .await;
        } else {
            sqlx::query(r#"UPDATE users SET "lateCancelStrikeCount" = $1 WHERE id = $2"#)
                .bind(new_strike)
                .bind(customer_id)
                .execute(&mut **tx)
                .await?;
        }
    } else {
        sqlx::query(r#"UPDATE users SET "lateCancelStrikeCount" = $1 WHERE id = $2"#)
            .bind(new_strike)
            .bind(customer_id)
            .execute(&mut **tx)
            .await?;
    }

    Ok((
        new_strike,
        instant_help_blocked,
        compensation_amount,
        compensation_distance,
    ))
}

pub async fn cancel_booking(
    state: &AppState,
    booking_id: &str,
    reason: &str,
    source: &str,
    opts: CancelOptions,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;

    let initial = sqlx::query(
        r#"SELECT status::text AS status FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;
    let initial_status = initial.get::<String, _>("status");
    if initial_status == "COMPLETED" {
        return Err(AppError::BadRequest(
            "Completed bookings cannot be cancelled.".into(),
        ));
    }
    let started_as_match = matching_status(&initial_status);

    let mut late_cancel_strike = false;
    let mut strike_count: Option<i32> = None;
    let mut instant_help_blocked = false;
    let mut compensation_amount: Option<i32> = None;
    let mut compensation_distance: Option<f64> = None;
    let mut free_due_to_no_progress = false;
    let refund_amount = 0;
    let refund_method = "NONE";
    let mut cancel_reason = reason.to_string();
    let mut outbox_source = source.to_string();
    let mut operator_id_str: Option<String> = None;
    let mut operator_name: Option<String> = None;
    let mut customer_id_str: Option<String> = None;

    let mut tx = state.db.begin().await?;

    let locked = sqlx::query(
        r#"SELECT id, status::text AS status, "customerId", "operatorId", "isPaid",
                  amount, "paymentMethod", "acceptedAt", "workerNoProgressAt",
                  "serviceLat", "serviceLng"
           FROM bookings WHERE id = $1 FOR UPDATE"#,
    )
    .bind(bid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let status = locked.get::<String, _>("status");
    if status == "COMPLETED" {
        tx.rollback().await?;
        return Err(AppError::BadRequest(
            "Completed bookings cannot be cancelled.".into(),
        ));
    }
    if status == "CANCELLED" {
        tx.rollback().await?;
        return Err(AppError::BadRequest("Booking is already cancelled.".into()));
    }

    if source == "customer"
        && !opts.skip_stage_gate
        && started_as_match
        && !matching_status(&status)
    {
        tx.rollback().await?;
        return Err(AppError::BadRequest(
            "This request was already accepted. Refresh to continue or cancel the accepted job."
                .into(),
        ));
    }

    let worker_no_progress_at = timestamp_utc(&locked, "workerNoProgressAt");
    free_due_to_no_progress =
        source == "customer" && worker_no_progress_at.is_some() && status == "ACCEPTED";

    let apply_strike = source == "customer"
        && opts.apply_late_cancel_strike
        && !free_due_to_no_progress;

    if source == "customer" && !opts.skip_stage_gate {
        if status == "ARRIVED" || status == "ACTIVE" || status == "IN_PROGRESS" {
            tx.rollback().await?;
            return Err(AppError::BadRequest(
                "This job has already started or the pro has arrived. Ask your pro to approve a cancellation instead.".into(),
            ));
        }
        if status == "ACCEPTED"
            && !free_due_to_no_progress
            && !is_within_cancel_grace(timestamp_utc(&locked, "acceptedAt"))
        {
            late_cancel_strike = apply_strike;
        }
    }

    cancel_reason = if free_due_to_no_progress {
        format!("{} [WORKER_NO_PROGRESS]", reason)
    } else {
        reason.to_string()
    };
    outbox_source = if free_due_to_no_progress {
        "WORKER_NO_PROGRESS".to_string()
    } else {
        source.to_string()
    };

    let customer_id = locked.get::<Uuid, _>("customerId");
    let operator_id = locked.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
    customer_id_str = Some(customer_id.to_string());
    operator_id_str = operator_id.map(|u| u.to_string());

    if let Some(op) = operator_id {
        operator_name = sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
            .bind(op)
            .fetch_optional(&mut *tx)
            .await?;
    }

    let should_refund_credit = source == "customer"
        && operator_id.is_some()
        && opts.refund_job_credit
        && !free_due_to_no_progress;

    sqlx::query(
        r#"UPDATE bookings SET status = 'CANCELLED', "cancellationReason" = $1, "cancelRequestedAt" = NULL WHERE id = $2"#,
    )
    .bind(&cancel_reason)
    .bind(bid)
    .execute(&mut *tx)
    .await?;

    if should_refund_credit {
        if let Some(op) = operator_id {
            refund_credit(&mut tx, op, bid, "REFUND_CUSTOMER_CANCEL").await?;
        }
    }

    if late_cancel_strike {
        let service_lat = locked
            .try_get::<Option<rust_decimal::Decimal>, _>("serviceLat")
            .ok()
            .flatten();
        let service_lng = locked
            .try_get::<Option<rust_decimal::Decimal>, _>("serviceLng")
            .ok()
            .flatten();
        let (sc, blocked, comp_amt, comp_dist) = apply_late_cancel_strike(
            state,
            &mut tx,
            customer_id,
            bid,
            operator_id,
            service_lat,
            service_lng,
        )
        .await?;
        strike_count = Some(sc);
        instant_help_blocked = blocked;
        compensation_amount = comp_amt;
        compensation_distance = comp_dist;
    }

    let outbox_payload = json!({
        "bookingId": booking_id,
        "reason": cancel_reason,
        "source": outbox_source,
        "operatorId": operator_id_str,
        "operatorName": operator_name,
        "customerId": customer_id_str,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts)
           VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.cancelled")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;

    publish_cancelled(
        state,
        booking_id,
        operator_id_str.as_deref(),
        operator_name.as_deref(),
        customer_id_str.as_deref(),
    )
    .await;

    let message = if free_due_to_no_progress {
        "Booking cancelled at no cost — your pro was not making progress toward you.".to_string()
    } else if late_cancel_strike {
        if instant_help_blocked {
            format!(
                "Booking cancelled. This was a late cancel (strike {}). Instant Help is blocked until you pay travel compensation.",
                strike_count.unwrap_or(0)
            )
        } else {
            format!(
                "Booking cancelled. Late cancel recorded (strike {} of {}).",
                strike_count.unwrap_or(0),
                LATE_CANCEL_STRIKE_THRESHOLD
            )
        }
    } else {
        "Booking cancelled".to_string()
    };

    Ok(json!({
        "status": "CANCELLED",
        "refundAmount": refund_amount,
        "refundMethod": refund_method,
        "message": message,
        "lateCancelStrike": late_cancel_strike,
        "strikeCount": strike_count,
        "instantHelpBlocked": if instant_help_blocked { json!(true) } else { Value::Null },
        "compensationAmount": compensation_amount,
        "compensationDistanceKm": compensation_distance,
        "workerNoProgress": free_due_to_no_progress,
    }))
}

pub async fn timeout_cancel_booking(state: &AppState, booking_id: &str) -> Result<bool, String> {
    let bid = Uuid::parse_str(booking_id).map_err(|e| e.to_string())?;
    let mut tx = state.db.begin().await.map_err(|e| e.to_string())?;

    let result = sqlx::query(
        r#"UPDATE bookings SET status = 'CANCELLED', "cancellationReason" = 'No worker accepted in time'
           WHERE id = $1 AND status = 'REQUESTED'"#,
    )
    .bind(bid)
    .execute(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    if result.rows_affected() == 0 {
        tx.rollback().await.map_err(|e| e.to_string())?;
        return Ok(false);
    }

    let row = sqlx::query(
        r#"SELECT "customerId", "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten()
        .map(|u| u.to_string());

    let outbox_payload = json!({
        "bookingId": booking_id,
        "reason": "No worker accepted in time",
        "source": "timeout",
        "operatorId": operator_id,
        "operatorName": null,
        "customerId": customer_id,
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts)
           VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.cancelled")
    .bind(bid)
    .bind(outbox_payload)
    .execute(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    tx.commit().await.map_err(|e| e.to_string())?;

    publish_cancelled(
        state,
        booking_id,
        operator_id.as_deref(),
        None,
        Some(&customer_id),
    )
    .await;

    Ok(true)
}

pub async fn request_cancel(
    state: &AppState,
    booking_id: &str,
    customer_user_id: &str,
    reason: Option<&str>,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let uid = Uuid::parse_str(customer_user_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "customerId", "operatorId", "cancelRequestedAt"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.get::<Uuid, _>("customerId") != uid {
        return Err(AppError::BadRequest(
            "Only the customer can request cancellation".into(),
        ));
    }

    let status = row.get::<String, _>("status");
    if !matches!(
        status.as_str(),
        "ACCEPTED" | "ARRIVED" | "ACTIVE" | "IN_PROGRESS"
    ) {
        return Err(AppError::BadRequest(
            "Cancel request is only available after a pro has accepted the job".into(),
        ));
    }

    if timestamp_utc(&row, "cancelRequestedAt").is_some() {
        return Ok(json!({
            "cancelRequested": true,
            "message": "Cancel request already pending",
        }));
    }

    sqlx::query(
        r#"UPDATE bookings SET "cancelRequestedAt" = NOW(), "cancellationReason" = COALESCE($1, "cancellationReason") WHERE id = $2"#,
    )
    .bind(reason)
    .bind(bid)
    .execute(&state.db)
    .await?;

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
        &status,
        operator_id.as_deref(),
        operator_name.as_deref(),
        Some(customer_user_id),
        true,
    )
    .await;

    if let Some(op) = operator_id.as_ref() {
        state
            .fcm
            .send_to_user(
                state,
                op,
                "Cancellation requested",
                "The customer asked to cancel this job. Approve or decline in the app.",
                Some(&[("type", "cancel_requested"), ("bookingId", booking_id)]),
            )
            .await;
    }

    Ok(json!({
        "cancelRequested": true,
        "message": "Cancel request sent to your pro",
    }))
}

pub async fn approve_cancel_request(
    state: &AppState,
    booking_id: &str,
    operator_user_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let op = Uuid::parse_str(operator_user_id)?;

    let row = sqlx::query(
        r#"SELECT "operatorId", "cancelRequestedAt", "cancellationReason" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() != Some(op) {
        return Err(AppError::BadRequest(
            "Only the assigned worker can approve cancellation".into(),
        ));
    }
    if timestamp_utc(&row, "cancelRequestedAt").is_none() {
        return Err(AppError::BadRequest("No pending cancel request".into()));
    }

    let reason = row
        .get::<Option<String>, _>("cancellationReason")
        .unwrap_or_else(|| "Cancelled by mutual agreement".to_string());

    cancel_booking(
        state,
        booking_id,
        &reason,
        "customer",
        CancelOptions {
            apply_late_cancel_strike: false,
            skip_stage_gate: true,
            refund_job_credit: true,
        },
    )
    .await
}

pub async fn decline_cancel_request(
    state: &AppState,
    booking_id: &str,
    operator_user_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let op = Uuid::parse_str(operator_user_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "customerId", "operatorId", "cancelRequestedAt" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() != Some(op) {
        return Err(AppError::BadRequest(
            "Only the assigned worker can decline cancellation".into(),
        ));
    }
    if timestamp_utc(&row, "cancelRequestedAt").is_none() {
        return Err(AppError::BadRequest("No pending cancel request".into()));
    }

    let status = row.get::<String, _>("status");
    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let operator_name: Option<String> = sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
        .bind(op)
        .fetch_optional(&state.db)
        .await?;

    sqlx::query(r#"UPDATE bookings SET "cancelRequestedAt" = NULL WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;

    cache_and_emit_status(
        state,
        booking_id,
        &status,
        Some(operator_user_id),
        operator_name.as_deref(),
        Some(&customer_id),
        false,
    )
    .await;

    state
        .fcm
        .send_to_user(
            state,
            &customer_id,
            "Cancel declined",
            "Your pro declined the cancellation — the job continues.",
            Some(&[("type", "cancel_declined"), ("bookingId", booking_id)]),
        )
        .await;

    Ok(json!({
        "cancelRequested": false,
        "message": "Cancel request declined",
    }))
}

pub async fn withdraw_cancel_request(
    state: &AppState,
    booking_id: &str,
    customer_user_id: &str,
) -> AppResult<Value> {
    let bid = Uuid::parse_str(booking_id)?;
    let uid = Uuid::parse_str(customer_user_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "customerId", "operatorId", "cancelRequestedAt" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.get::<Uuid, _>("customerId") != uid {
        return Err(AppError::BadRequest(
            "Only the customer can withdraw a cancel request".into(),
        ));
    }
    if timestamp_utc(&row, "cancelRequestedAt").is_none() {
        return Ok(json!({
            "cancelRequested": false,
            "message": "No pending cancel request",
        }));
    }

    let status = row.get::<String, _>("status");
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

    sqlx::query(r#"UPDATE bookings SET "cancelRequestedAt" = NULL WHERE id = $1"#)
        .bind(bid)
        .execute(&state.db)
        .await?;

    cache_and_emit_status(
        state,
        booking_id,
        &status,
        operator_id.as_deref(),
        operator_name.as_deref(),
        Some(customer_user_id),
        false,
    )
    .await;

    Ok(json!({
        "cancelRequested": false,
        "message": "Cancel request withdrawn",
    }))
}

pub async fn get_late_cancel_compensation_quote(
    state: &AppState,
    user_id: &str,
) -> AppResult<Value> {
    let uid = Uuid::parse_str(user_id)?;
    let row = sqlx::query(
        r#"SELECT "instantHelpBlocked", "unblockCompensationAmountInr",
                  "unblockCompensationDistanceKm", "unblockCompensationBookingId"
           FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    let blocked = row.get::<bool, _>("instantHelpBlocked");
    if !blocked {
        return Ok(json!({
            "blocked": false,
            "amountInr": null,
            "distanceKm": null,
            "bookingId": null,
            "workerName": null,
        }));
    }
    let booking_id = row
        .try_get::<Option<Uuid>, _>("unblockCompensationBookingId")
        .ok()
        .flatten();
    let worker_name: Option<String> = if let Some(bid) = booking_id {
        sqlx::query_scalar(
            r#"SELECT u.name FROM bookings b
               JOIN users u ON u.id = b."operatorId"
               WHERE b.id = $1"#,
        )
        .bind(bid)
        .fetch_optional(&state.db)
        .await?
    } else {
        None
    };
    Ok(json!({
        "blocked": true,
        "amountInr": row.get::<Option<i32>, _>("unblockCompensationAmountInr"),
        "distanceKm": row
            .try_get::<Option<rust_decimal::Decimal>, _>("unblockCompensationDistanceKm")
            .ok()
            .flatten(),
        "bookingId": booking_id.map(|u| u.to_string()),
        "workerName": worker_name,
    }))
}

pub async fn mark_late_cancel_compensation_paid(
    state: &AppState,
    customer_user_id: &str,
) -> AppResult<()> {
    let uid = Uuid::parse_str(customer_user_id)?;
    let row = sqlx::query(
        r#"SELECT "instantHelpBlocked", "unblockCompensationBookingId",
                  "unblockCompensationAmountInr", "unblockCompensationDistanceKm"
           FROM users WHERE id = $1"#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("User not found".into()))?;

    if !row.get::<bool, _>("instantHelpBlocked") {
        return Ok(());
    }

    let booking_id = row
        .try_get::<Option<Uuid>, _>("unblockCompensationBookingId")
        .ok()
        .flatten();
    let amount = row.get::<Option<i32>, _>("unblockCompensationAmountInr").unwrap_or(0);
    let distance_km = row
        .try_get::<Option<rust_decimal::Decimal>, _>("unblockCompensationDistanceKm")
        .ok()
        .flatten();

    sqlx::query(
        r#"UPDATE users SET
            "instantHelpBlocked" = false,
            "lateCancelStrikeCount" = 0,
            "unblockCompensationBookingId" = NULL,
            "unblockCompensationAmountInr" = NULL,
            "unblockCompensationDistanceKm" = NULL
           WHERE id = $1"#,
    )
    .bind(uid)
    .execute(&state.db)
    .await?;

    let worker_id: Option<Uuid> = if let Some(bid) = booking_id {
        sqlx::query(
            r#"UPDATE bookings SET
                "lateCancelCompensationPaidAt" = NOW(),
                "lateCancelCompensationAmountInr" = $1,
                "lateCancelCompensationDistanceKm" = $2
               WHERE id = $3"#,
        )
        .bind(amount)
        .bind(distance_km)
        .bind(bid)
        .execute(&state.db)
        .await?;

        sqlx::query_scalar(r#"SELECT "operatorId" FROM bookings WHERE id = $1"#)
            .bind(bid)
            .fetch_optional(&state.db)
            .await?
    } else {
        None
    };

    if let Some(wid) = worker_id {
        let booking_id_str = booking_id.map(|u| u.to_string()).unwrap_or_default();
        let amount_str = amount.to_string();
        state
            .fcm
            .send_to_user(
                state,
                &wid.to_string(),
                "Travel compensation received",
                &format!(
                    "A customer paid ₹{} travel compensation for a late-cancelled job.",
                    amount
                ),
                Some(&[
                    ("type", "late_cancel_compensation_paid"),
                    ("bookingId", &booking_id_str),
                    ("amount", &amount_str),
                ]),
            )
            .await;
    }

    Ok(())
}
