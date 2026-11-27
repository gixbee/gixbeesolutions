use std::time::Duration;

use sqlx::Row;
use tracing::{info, warn};
use uuid::Uuid;

use crate::bookings::{progress, rebroadcast_booking, timeout_cancel_booking};
use crate::state::AppState;

pub async fn run_scheduler(state:AppState) {
    let mut interval=tokio::time::interval(Duration::from_secs(5));
    loop {
        interval.tick().await;
        if let Err(e)=poll(&state).await {warn!("booking deadlines: {}",e);}
    }
}

async fn poll(state:&AppState)->Result<(),String> {
    if let Err(error) = maintain_deadlines(state).await {
        warn!(%error, "Booking deadline maintenance failed");
    }
    for _ in 0..25 {
        let job = sqlx::query(
            r#"WITH candidate AS (
                   SELECT id FROM booking_deadlines
                   WHERE "processedAt" IS NULL AND "dueAt" <= NOW()
                     AND ("leaseUntil" IS NULL OR "leaseUntil" <= NOW())
                   ORDER BY "dueAt", id LIMIT 1 FOR UPDATE SKIP LOCKED
               )
               UPDATE booking_deadlines d SET "leaseUntil"=NOW()+INTERVAL '60 seconds',
                   attempts=d.attempts+1
               FROM candidate c WHERE d.id=c.id
               RETURNING d.id,d."bookingId",d.kind,d.sequence,d.attempts"#,
        )
        .fetch_optional(&state.db).await.map_err(|error| error.to_string())?;
        let Some(job) = job else { break };
        let id: Uuid = job.get("id");
        let bid = job.get::<Uuid, _>("bookingId").to_string();
        let sequence: i32 = job.get("sequence");
        let attempts: i32 = job.get("attempts");
        let kind: String = job.get("kind");
        let result = tokio::time::timeout(Duration::from_secs(40), async {
            match kind.as_str() {
                "TIMEOUT" => handle_request_timeout(state, &bid, sequence as u32).await,
                "REMINDER" => handle_seven_minute_reminder(state, &bid).await,
                "GPS" => handle_ten_minute_gps_check(state, &bid, sequence-1).await,
                _ => Err("Unknown deadline kind".to_string()),
            }
        }).await.unwrap_or_else(|_| Err("Deadline handler timed out".into()));

        let failure = result.err().map(|error| {
            warn!(%id, %error, "Booking deadline failed");
            error.chars().take(2000).collect::<String>()
        });
        sqlx::query(
            r#"UPDATE booking_deadlines SET "leaseUntil"=NULL,
                      "processedAt"=CASE WHEN $3::text IS NULL THEN NOW() END,
                      "lastError"=$3,
                      "dueAt"=CASE WHEN $3 IS NULL THEN "dueAt" ELSE NOW()+INTERVAL '30 seconds' END
               WHERE id=$1 AND attempts=$2 AND "processedAt" IS NULL"#,
        )
        .bind(id).bind(attempts).bind(failure)
        .execute(&state.db).await.map_err(|error| error.to_string())?;
    }
    Ok(())
}

async fn maintain_deadlines(state: &AppState) -> Result<(), sqlx::Error> {
    let mut tx = state.db.begin().await?;
    let claimed = sqlx::query(
        r#"UPDATE booking_maintenance SET "nextRunAt"=NOW()+INTERVAL '5 minutes'
           WHERE id=true AND "nextRunAt"<=NOW()"#,
    ).execute(&mut *tx).await?;
    if claimed.rows_affected() == 0 {
        return Ok(());
    }
    // Repair missing jobs from old releases. New state transitions enqueue them directly.
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT b.id,'TIMEOUT',s.n,b."createdAt"+s.n*INTERVAL '90 seconds'
        FROM bookings b CROSS JOIN (VALUES (1),(2)) s(n) WHERE b.status='REQUESTED' AND b.type='INSTANT'
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&mut *tx).await?;
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT id,'REMINDER',1,("acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '7 minutes'
        FROM bookings WHERE status='ACCEPTED' AND "acceptedAt" IS NOT NULL
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&mut *tx).await?;
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT b.id,'GPS',b."gpsStrikes"+1,CASE WHEN b."gpsStrikes"=0 THEN (b."acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '10 minutes'
          ELSE COALESCE((SELECT d."processedAt" FROM booking_deadlines d WHERE d."bookingId"=b.id AND d.kind='GPS'
            AND d.sequence=b."gpsStrikes"),NOW())+INTERVAL '3 minutes' END
        FROM bookings b WHERE b.status='ACCEPTED' AND b."acceptedAt" IS NOT NULL AND b."workerNoProgressAt" IS NULL AND b."gpsStrikes"<3
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&mut *tx).await?;
    sqlx::query(r#"WITH expired AS (
        SELECT booking_id,worker_id FROM booking_offer_recipients WHERE expires_at<NOW()-INTERVAL '30 days'
        ORDER BY expires_at LIMIT 1000 FOR UPDATE SKIP LOCKED
    ) DELETE FROM booking_offer_recipients o USING expired x
       WHERE o.booking_id=x.booking_id AND o.worker_id=x.worker_id"#)
        .execute(&mut *tx).await?;
    sqlx::query(r#"WITH finished AS (
        SELECT d.id FROM booking_deadlines d JOIN bookings b ON b.id=d."bookingId"
        WHERE d."processedAt"<NOW()-INTERVAL '30 days' AND b.status IN ('COMPLETED','CANCELLED','REJECTED')
        ORDER BY d."processedAt" LIMIT 1000 FOR UPDATE OF d SKIP LOCKED
    ) DELETE FROM booking_deadlines d USING finished f WHERE d.id=f.id"#)
        .execute(&mut *tx).await?;
    sqlx::query(r#"WITH finished AS (
        SELECT id FROM outbox_events WHERE status='processed' AND "processedAt"<NOW()-INTERVAL '30 days'
          AND type IN ('booking.broadcast_created','booking.accepted','booking.cancelled',
            'booking.completed','booking.payment_confirmed','booking.gps_progress','marketplace.notify')
        ORDER BY "processedAt" LIMIT 1000 FOR UPDATE SKIP LOCKED
    ) DELETE FROM outbox_events e USING finished f WHERE e.id=f.id"#)
        .execute(&mut *tx).await?;
    tx.commit().await
}

async fn handle_seven_minute_reminder(state: &AppState, booking_id: &str) -> Result<(), String> {
    let bid = Uuid::parse_str(booking_id).map_err(|e| e.to_string())?;
    let row = sqlx::query(r#"SELECT status::text AS status, "operatorId" FROM bookings WHERE id = $1"#)
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

async fn handle_ten_minute_gps_check(state: &AppState, booking_id: &str, expected_strikes:i32) -> Result<(), String> {
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

    let result = progress::add_gps_strike(state, booking_id,expected_strikes)
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
    let row = sqlx::query(r#"SELECT status::text AS status, "operatorId" FROM bookings WHERE id = $1"#)
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
