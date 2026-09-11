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
    // Reconstruct missing work from committed booking state on every poll.
    // No process timer or post-commit enqueue is required for correctness.
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT b.id,'TIMEOUT',s.n,(b."createdAt" AT TIME ZONE 'UTC')+s.n*INTERVAL '90 seconds'
        FROM bookings b CROSS JOIN (VALUES (1),(2)) s(n) WHERE b.status='REQUESTED' AND b.type='INSTANT'
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&state.db).await.map_err(|e|e.to_string())?;
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT id,'REMINDER',1,("acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '7 minutes'
        FROM bookings WHERE status='ACCEPTED' AND "acceptedAt" IS NOT NULL
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&state.db).await.map_err(|e|e.to_string())?;
    sqlx::query(r#"INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT b.id,'GPS',b."gpsStrikes"+1,CASE WHEN b."gpsStrikes"=0 THEN (b."acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '10 minutes'
          ELSE COALESCE((SELECT d."processedAt" FROM booking_deadlines d WHERE d."bookingId"=b.id AND d.kind='GPS'
            AND d.sequence=b."gpsStrikes"),NOW())+INTERVAL '3 minutes' END
        FROM bookings b WHERE b.status='ACCEPTED' AND b."acceptedAt" IS NOT NULL AND b."workerNoProgressAt" IS NULL AND b."gpsStrikes"<3
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING"#).execute(&state.db).await.map_err(|e|e.to_string())?;
    for _ in 0..25 {
        let mut tx=state.db.begin().await.map_err(|e|e.to_string())?;
        let job=sqlx::query(r#"SELECT id,"bookingId",kind,sequence,attempts FROM booking_deadlines
            WHERE "processedAt" IS NULL AND "dueAt"<=NOW() ORDER BY "dueAt" LIMIT 1 FOR UPDATE SKIP LOCKED"#)
            .fetch_optional(&mut *tx).await.map_err(|e|e.to_string())?;
        let Some(job)=job else {break};
        let id:Uuid=job.get("id");let bid=job.get::<Uuid,_>("bookingId").to_string();let sequence=job.get::<i32,_>("sequence");
        let result=match job.get::<String,_>("kind").as_str() {
            "TIMEOUT"=>handle_request_timeout(state,&bid,sequence as u32).await,
            "REMINDER"=>handle_seven_minute_reminder(state,&bid).await,
            "GPS"=>handle_ten_minute_gps_check(state,&bid,sequence-1).await,
            _=>Err("Unknown deadline kind".to_string()),
        };
        match result {
            Ok(())=>{sqlx::query(r#"UPDATE booking_deadlines SET "processedAt"=NOW(),attempts=attempts+1,"lastError"=NULL WHERE id=$1"#)
                .bind(id).execute(&mut *tx).await.map_err(|e|e.to_string())?;},
            Err(e)=>{warn!("booking deadline {}: {}",id,e);
                sqlx::query(r#"UPDATE booking_deadlines SET attempts=attempts+1,"lastError"=$2,"dueAt"=NOW()+INTERVAL '30 seconds' WHERE id=$1"#)
                    .bind(id).bind(e.chars().take(2000).collect::<String>()).execute(&mut *tx).await.map_err(|e|e.to_string())?;},
        }
        tx.commit().await.map_err(|e|e.to_string())?;
    }
    Ok(())
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
