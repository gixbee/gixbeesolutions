use rust_decimal::prelude::ToPrimitive;
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::redis::WorkerLocationSnapshot;
use crate::state::AppState;
use crate::workers;

const GPS_LOCATION_MAX_AGE_MS: i64 = 90_000;
const PROGRESS_NEAR_JOB_KM: f64 = 0.5;
const PROGRESS_MIN_CLOSER_KM: f64 = 0.3;
const PROGRESS_STRIKE_THRESHOLD: i32 = 2;

pub struct ProgressEvaluation {
    pub progressing: bool,
    pub reason: String,
    pub distance_km: Option<f64>,
}

pub fn evaluate_worker_progress(
    service_lat: Option<f64>,
    service_lng: Option<f64>,
    accept_distance_km: Option<f64>,
    location: Option<&WorkerLocationSnapshot>,
    now_ms: i64,
) -> ProgressEvaluation {
    let location = match location {
        Some(loc) if loc.lat.is_finite() && loc.lng.is_finite() => loc,
        _ => {
            return ProgressEvaluation {
                progressing: false,
                reason: "No recent location update found.".into(),
                distance_km: None,
            };
        }
    };

    if let Some(ts) = location.timestamp_ms {
        let age = now_ms - ts;
        if age > GPS_LOCATION_MAX_AGE_MS {
            return ProgressEvaluation {
                progressing: false,
                reason: "Location update is stale (GPS not fresh).".into(),
                distance_km: None,
            };
        }
    }

    let job_lat = service_lat.filter(|v| v.is_finite());
    let job_lng = service_lng.filter(|v| v.is_finite());
    if job_lat.is_none() || job_lng.is_none() {
        return ProgressEvaluation {
            progressing: true,
            reason: "No job coordinates — skip check.".into(),
            distance_km: None,
        };
    }

    let distance_km = haversine_km(location.lat, location.lng, job_lat.unwrap(), job_lng.unwrap());
    if distance_km <= PROGRESS_NEAR_JOB_KM {
        return ProgressEvaluation {
            progressing: true,
            reason: format!("Worker is near the job ({:.2} km).", distance_km),
            distance_km: Some(distance_km),
        };
    }

    if let Some(accept_dist) = accept_distance_km.filter(|d| d.is_finite()) {
        let closer_by = accept_dist - distance_km;
        if closer_by >= PROGRESS_MIN_CLOSER_KM {
            return ProgressEvaluation {
                progressing: true,
                reason: format!("Worker moved {:.2} km closer.", closer_by),
                distance_km: Some(distance_km),
            };
        }
        return ProgressEvaluation {
            progressing: false,
            reason: format!(
                "Worker has not progressed (only {:.2} km closer; still {:.2} km away).",
                closer_by,
                distance_km
            ),
            distance_km: Some(distance_km),
        };
    }

    if distance_km <= 5.0 {
        return ProgressEvaluation {
            progressing: true,
            reason: "Within 5 km (legacy, no accept baseline).".into(),
            distance_km: Some(distance_km),
        };
    }

    ProgressEvaluation {
        progressing: false,
        reason: format!(
            "Worker is too far ({:.2} km) without accept baseline.",
            distance_km
        ),
        distance_km: Some(distance_km),
    }
}

pub struct GpsStrikeResult {
    pub strikes: i32,
    pub free_cancel_enabled: bool,
}

pub async fn add_gps_strike(state: &AppState, booking_id: &str) -> AppResult<Option<GpsStrikeResult>> {
    let bid = Uuid::parse_str(booking_id)?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, "gpsStrikes", "workerNoProgressAt",
                  "customerId", "operatorId", skill
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?;

    let row = match row {
        Some(r) => r,
        None => return Ok(None),
    };

    if row.get::<String, _>("status") != "ACCEPTED" {
        return Ok(None);
    }

    let strikes = row.get::<i32, _>("gpsStrikes");
    if row
        .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("workerNoProgressAt")
        .ok()
        .flatten()
        .is_some()
    {
        return Ok(Some(GpsStrikeResult {
            strikes,
            free_cancel_enabled: true,
        }));
    }

    let new_strikes = strikes + 1;
    if new_strikes >= PROGRESS_STRIKE_THRESHOLD {
        sqlx::query(
            r#"UPDATE bookings SET "gpsStrikes" = $1, "workerNoProgressAt" = NOW() WHERE id = $2"#,
        )
        .bind(new_strikes)
        .bind(bid)
        .execute(&state.db)
        .await?;

        let customer_id = row.get::<Uuid, _>("customerId").to_string();
        let operator_id = row
            .try_get::<Option<Uuid>, _>("operatorId")
            .ok()
            .flatten()
            .map(|u| u.to_string());
        let skill = row.get::<String, _>("skill");
        let operator_name: Option<String> = if let Some(op) = operator_id.as_ref() {
            sqlx::query_scalar(r#"SELECT name FROM users WHERE id = $1"#)
                .bind(Uuid::parse_str(op)?)
                .fetch_optional(&state.db)
                .await?
        } else {
            None
        };

        emit_worker_no_progress(
            state,
            booking_id,
            &customer_id,
            operator_id.as_deref(),
            operator_name.as_deref(),
        )
        .await;

        state
            .fcm
            .send_to_user(
                state,
                &customer_id,
                "Pro not moving",
                "Your pro does not appear to be heading your way. You can cancel this booking at no cost.",
                Some(&[("type", "worker_no_progress"), ("bookingId", booking_id)]),
            )
            .await;

        if let Some(op) = operator_id.as_ref() {
            state
                .fcm
                .send_to_user(
                    state,
                    op,
                    "No progress detected",
                    "GPS shows you have not moved toward the customer. They can now cancel free, and a strike was recorded.",
                    Some(&[("type", "worker_no_progress"), ("bookingId", booking_id)]),
                )
                .await;

            let reason = format!(
                "A {} job showed no GPS progress toward the customer; customer may cancel free.",
                skill
            );
            let _ = workers::record_strike(state, op, "GPS_FORFEIT", booking_id, &reason).await;
        }

        return Ok(Some(GpsStrikeResult {
            strikes: new_strikes,
            free_cancel_enabled: true,
        }));
    }

    sqlx::query(r#"UPDATE bookings SET "gpsStrikes" = $1 WHERE id = $2"#)
        .bind(new_strikes)
        .bind(bid)
        .execute(&state.db)
        .await?;

    if let Some(op) = row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() {
        let strike_str = new_strikes.to_string();
        state
            .fcm
            .send_to_user(
                state,
                &op.to_string(),
                "GPS Warning",
                &format!(
                    "Strike {}/3: Please head to the service location or the job will be forfeited.",
                    new_strikes
                ),
                Some(&[("type", "gps_strike"), ("strike", &strike_str)]),
            )
            .await;
    }

    Ok(Some(GpsStrikeResult {
        strikes: new_strikes,
        free_cancel_enabled: false,
    }))
}

async fn emit_worker_no_progress(
    state: &AppState,
    booking_id: &str,
    customer_id: &str,
    operator_id: Option<&str>,
    operator_name: Option<&str>,
) {
    let patch = json!({
        "status": "ACCEPTED",
        "bookingId": booking_id,
        "id": booking_id,
        "operatorId": operator_id,
        "operatorName": operator_name,
        "customerId": customer_id,
        "workerNoProgress": true,
    });
    let _ = state.redis.cache_booking_status(booking_id, &patch).await;
    state
        .realtime
        .emit_to_user(customer_id, "booking_status_update", &patch)
        .await;
    if let Some(oid) = operator_id {
        state
            .realtime
            .emit_to_user(oid, "booking_status_update", &patch)
            .await;
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

pub async fn load_progress_context(
    state: &AppState,
    booking_id: &str,
) -> AppResult<Option<(Uuid, Option<WorkerLocationSnapshot>, Option<f64>, Option<f64>, Option<f64>)>> {
    let bid = Uuid::parse_str(booking_id)?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, "operatorId", "serviceLat", "serviceLng",
                  "acceptDistanceKm", "workerNoProgressAt"
           FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?;

    let row = match row {
        Some(r) => r,
        None => return Ok(None),
    };

    if row.get::<String, _>("status") != "ACCEPTED" {
        return Ok(None);
    }
    if row
        .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("workerNoProgressAt")
        .ok()
        .flatten()
        .is_some()
    {
        return Ok(None);
    }

    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();
    let worker_id = match operator_id {
        Some(id) => id,
        None => return Ok(None),
    };

    let service_lat = row
        .try_get::<Option<rust_decimal::Decimal>, _>("serviceLat")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64());
    let service_lng = row
        .try_get::<Option<rust_decimal::Decimal>, _>("serviceLng")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64());
    let accept_distance = row
        .try_get::<Option<rust_decimal::Decimal>, _>("acceptDistanceKm")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64());

    let location = state
        .redis
        .get_worker_location_detail(&worker_id.to_string())
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(Some((worker_id, location, service_lat, service_lng, accept_distance)))
}
