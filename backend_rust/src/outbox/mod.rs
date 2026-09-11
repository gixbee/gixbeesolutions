mod booking_lifecycle;

use sqlx::Row;
use tracing::{error, warn};
use uuid::Uuid;

use crate::state::AppState;

const MAX_ATTEMPTS: i32 = 10;
const POLL_LIMIT: i64 = 25;

pub async fn run_poller(state: AppState) {
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));
    loop {
        interval.tick().await;
        if let Err(e) = poll_once(&state).await {
            warn!("outbox poll error: {}", e);
        }
    }
}

async fn poll_once(state: &AppState) -> Result<(), String> {
    let rows = sqlx::query(
        r#"SELECT id FROM outbox_events WHERE status = 'pending' AND attempts < $1 ORDER BY "createdAt" ASC LIMIT $2"#,
    )
    .bind(MAX_ATTEMPTS)
    .bind(POLL_LIMIT)
    .fetch_all(&state.db)
    .await
    .map_err(|e| e.to_string())?;

    for row in rows {
        let id: Uuid = row.get("id");
        if let Err(e) = dispatch_one(state, id).await {
            warn!("outbox dispatch {}: {}", id, e);
        }
    }
    Ok(())
}

async fn dispatch_one(state: &AppState, event_id: Uuid) -> Result<(), String> {
    let mut tx = state.db.begin().await.map_err(|e| e.to_string())?;
    let row = sqlx::query(
        r#"SELECT id, type, "aggregateId", payload, status, attempts FROM outbox_events WHERE id = $1 FOR UPDATE SKIP LOCKED"#,
    )
    .bind(event_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;

    let Some(row) = row else {
        return Ok(());
    };
    let status: String = row.get("status");
    if status == "processed" {
        return Ok(());
    }
    if status == "failed" {
        let attempts: i32 = row.get("attempts");
        if attempts >= MAX_ATTEMPTS {
            return Ok(());
        }
    }

    let attempts: i32 = row.get("attempts");
    let claimed = sqlx::query(
        r#"UPDATE outbox_events SET attempts = attempts + 1 WHERE id = $1 AND status = 'pending' AND attempts = $2"#,
    )
    .bind(event_id)
    .bind(attempts)
    .execute(&mut *tx)
    .await
    .map_err(|e| e.to_string())?;
    if claimed.rows_affected() == 0 {
        return Ok(());
    }

    let event_type: String = row.get("type");
    let payload = row.get::<serde_json::Value, _>("payload");

    match booking_lifecycle::handle(state, &event_type, &payload).await {
        Ok(()) => {
            sqlx::query(
                r#"UPDATE outbox_events SET status = 'processed', "processedAt" = NOW(), "lastError" = NULL WHERE id = $1"#,
            )
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        }
        Err(e) => {
            error!("outbox {} ({}) failed: {}", event_id, event_type, e);
            let new_attempts = attempts + 1;
            let terminal = new_attempts >= MAX_ATTEMPTS;
            let new_status = if terminal { "failed" } else { "pending" };
            sqlx::query(
                r#"UPDATE outbox_events SET status = $1, "lastError" = $2, "processedAt" = CASE WHEN $3 THEN NOW() ELSE NULL END WHERE id = $4"#,
            )
            .bind(new_status)
            .bind(e.chars().take(2000).collect::<String>())
            .bind(terminal)
            .bind(event_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| e.to_string())?;
        }
    }
    tx.commit().await.map_err(|e| e.to_string())?;
    Ok(())
}

pub async fn notify(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    aggregate_id: Uuid,
    user_id: Uuid,
    title: &str,
    body: &str,
    data: serde_json::Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(r#"INSERT INTO outbox_events (id,type,"aggregateId",payload) VALUES ($1,'marketplace.notify',$2,$3)"#)
        .bind(Uuid::new_v4()).bind(aggregate_id)
        .bind(serde_json::json!({"userId":user_id,"title":title,"body":body,"data":data}))
        .execute(&mut **tx).await?;
    Ok(())
}
