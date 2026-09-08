use std::time::Duration;

use serde_json::json;
use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

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
    let bid = Uuid::parse_str(booking_id).map_err(|e| e.to_string())?;
    let row = sqlx::query(r#"SELECT status FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| e.to_string())?;
    let row = row.ok_or_else(|| "booking not found".to_string())?;
    if row.get::<String, _>("status") != "ACCEPTED" {
        return Ok(());
    }
    info!(
        "GPS progress check for {} — full strike logic not yet ported",
        booking_id
    );
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
        info!(
            "Booking {} wave-1 timeout — rebroadcast not ported; scheduling final window",
            booking_id
        );
        schedule_request_timeout(state.clone(), booking_id.to_string(), 2);
        return Ok(());
    }

    let result = sqlx::query(
        r#"UPDATE bookings SET status = 'CANCELLED', "cancellationReason" = 'timeout' WHERE id = $1 AND status = 'REQUESTED'"#,
    )
    .bind(bid)
    .execute(&state.db)
    .await
    .map_err(|e| e.to_string())?;
    if result.rows_affected() == 0 {
        return Ok(());
    }

    let customer_id: Option<Uuid> =
        sqlx::query(r#"SELECT "customerId" FROM bookings WHERE id = $1"#)
            .bind(bid)
            .fetch_optional(&state.db)
            .await
            .map_err(|e| e.to_string())?
            .and_then(|r| r.try_get("customerId").ok());

    let payload = json!({
        "bookingId": booking_id,
        "reason": "timeout",
        "source": "timeout",
        "operatorId": null,
        "operatorName": null,
        "customerId": customer_id.map(|u| u.to_string()),
    });
    sqlx::query(
        r#"INSERT INTO outbox_events (type, "aggregateId", payload, status, attempts) VALUES ($1, $2, $3, 'pending', 0)"#,
    )
    .bind("booking.cancelled")
    .bind(bid)
    .bind(payload)
    .execute(&state.db)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}
