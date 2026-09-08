use std::time::Duration;

use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

use crate::bookings::{progress, rebroadcast_booking, timeout_cancel_booking};
use crate::state::AppState;

pub fn schedule_request_timeout(state: AppState, booking_id: String, attempt: u32) {
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(90)).await;
        if let Err(e) = handle_request_timeout(&state, &booking_id, attempt).await {
            warn!("requestTimeout {} attempt {}: {}", booking_id, attempt, e);
        }
    });
}

pub fn schedule_seven_minute_reminder(state: AppState, booking_id: String) {
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(7 * 60)).await;
        if let Err(e) = handle_seven_minute_reminder(&state, &booking_id).await {
            warn!("sevenMinuteReminder {}: {}", booking_id, e);
        }
    });
}

pub fn schedule_ten_minute_gps_check(state: AppState, booking_id: String) {
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(7 * 60)).await;
        if let Err(e) = handle_ten_minute_gps_check(&state, &booking_id).await {
            warn!("tenMinuteGpsCheck {}: {}", booking_id, e);
        }
    });
}

pub fn schedule_gps_recheck(state: AppState, booking_id: String) {
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(3 * 60)).await;
        if let Err(e) = handle_ten_minute_gps_check(&state, &booking_id).await {
            warn!("gpsRecheck {}: {}", booking_id, e);
        }
    });
}

async fn handle_seven_minute_reminder(state: &AppState, booking_id: &str) -> Result<(), String> {
    let bid = Uuid::parse_str(booking_id).map_err(|e| e.to_string())?;
    let row = sqlx::query(r#"SELECT status, "operatorId" FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| e.to_string())?;
    let row = row.ok_or_else(|| "booking not found".to_string())?;
    if row.get::<String, _>("status") != "ACCEPTED" {
        return Ok(());
    }
    if let Some(op) = row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() {
        state
            .fcm
            .send_to_user(
                state,
                &op.to_string(),
                "Reminder: Customer is waiting",
                "Please confirm you are on your way. Auto-check in 3 minutes.",
                None,
            )
            .await;
    }
    Ok(())
}

async fn handle_ten_minute_gps_check(state: &AppState, booking_id: &str) -> Result<(), String> {
    let ctx = progress::load_progress_context(state, booking_id)
        .await
        .map_err(|e| e.to_string())?;
    let (worker_id, location, service_lat, service_lng, accept_distance) = match ctx {
        Some(c) => c,
        None => return Ok(()),
    };

    let now_ms = chrono::Utc::now().timestamp_millis();
    let evaluation = progress::evaluate_worker_progress(
        service_lat,
        service_lng,
        accept_distance,
        location.as_ref(),
        now_ms,
    );

    if evaluation.progressing {
        info!(
            "Worker {} progress verified for {}: {}",
            worker_id,
            booking_id,
            evaluation.reason
        );
        return Ok(());
    }

    warn!(
        "GPS progress violation for booking {}: {}",
        booking_id,
        evaluation.reason
    );

    let result = progress::add_gps_strike(state, booking_id)
        .await
        .map_err(|e| e.to_string())?;

    match result {
        Some(r) if r.free_cancel_enabled => {
            info!(
                "Booking {}: customer free cancel enabled after strike {}",
                booking_id,
                r.strikes
            );
        }
        Some(r) => {
            schedule_gps_recheck(state.clone(), booking_id.to_string());
            info!(
                "Booking {}: strike {} issued, recheck in 3m",
                booking_id,
                r.strikes
            );
        }
        None => {}
    }

    Ok(())
}

async fn handle_request_timeout(
    state: &AppState,
    booking_id: &str,
    attempt: u32,
) -> Result<(), String> {
    let bid = Uuid::parse_str(booking_id).map_err(|e| e.to_string())?;
    let row = sqlx::query(r#"SELECT status, "operatorId" FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| e.to_string())?;
    let row = row.ok_or_else(|| "booking not found".to_string())?;
    if row.get::<String, _>("status") != "REQUESTED" {
        return Ok(());
    }
    let is_broadcast = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten()
        .is_none();
    if attempt < 2 && is_broadcast {
        let (still_open, notified) = rebroadcast_booking(state, booking_id)
            .await
            .map_err(|e| e.to_string())?;
        if !still_open {
            return Ok(());
        }
        info!(
            "Booking {} rebroadcast — {} new pros notified; final window running",
            booking_id,
            notified
        );
        return Ok(());
    }

    let cancelled = timeout_cancel_booking(state, booking_id)
        .await?;
    if cancelled {
        warn!(
            "Booking {} auto-cancelled — no worker accepted after the widened search",
            booking_id
        );
    }
    Ok(())
}
