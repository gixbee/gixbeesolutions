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
    sqlx::query(
        r#"UPDATE outbox_events SET status='failed', "processedAt"=NOW(),
                  "lastError"='Final delivery lease expired'
           WHERE status='processing' AND "availableAt" <= NOW() AND attempts >= $1"#,
    )
    .bind(MAX_ATTEMPTS)
    .execute(&state.db)
    .await
    .map_err(|e| e.to_string())?;

    for _ in 0..POLL_LIMIT {
        let row = sqlx::query(
            r#"WITH candidate AS (
                   SELECT id FROM outbox_events
                   WHERE status IN ('pending','processing') AND "availableAt" <= NOW() AND attempts < $1
                   ORDER BY "availableAt", "createdAt", id
                   LIMIT 1 FOR UPDATE SKIP LOCKED
               )
               UPDATE outbox_events e
               SET status='processing', attempts=e.attempts+1, "availableAt"=NOW()+INTERVAL '60 seconds'
               FROM candidate c WHERE e.id=c.id
               RETURNING e.id,e.type,e.payload,e.attempts"#,
        )
        .bind(MAX_ATTEMPTS)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| e.to_string())?;
        let Some(row) = row else { break };

        let id: Uuid = row.get("id");
        let event_type: String = row.get("type");
        let mut payload: serde_json::Value = row.get("payload");
        let attempts: i32 = row.get("attempts");
        if let Some(object) = payload.as_object_mut() {
            object.insert("eventId".into(), serde_json::json!(id));
        }
        let delivery = tokio::time::timeout(
            std::time::Duration::from_secs(40),
            booking_lifecycle::handle(state, &event_type, &payload),
        )
        .await
        .unwrap_or_else(|_| Err("Delivery timed out".into()));

        let (status, last_error, delay) = match delivery {
            Ok(()) => ("processed", None, 0),
            Err(e) => {
                error!(%id, %event_type, error = %e, "Outbox delivery failed");
                let status = if attempts >= MAX_ATTEMPTS { "failed" } else { "pending" };
                let delay = (5_i32 * 2_i32.pow((attempts - 1) as u32)).min(900);
                (status, Some(e.chars().take(2000).collect::<String>()), delay)
            }
        };
        sqlx::query(
            r#"UPDATE outbox_events SET status=$3, "lastError"=$4,
                      "availableAt"=NOW()+($5::integer * INTERVAL '1 second'),
                      "processedAt"=CASE WHEN $3 IN ('processed', 'failed') THEN NOW() END
               WHERE id=$1 AND status='processing' AND attempts=$2"#,
        )
        .bind(id)
        .bind(attempts)
        .bind(status)
        .bind(last_error)
        .bind(delay)
        .execute(&state.db)
        .await
        .map_err(|e| e.to_string())?;
    }
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
