//! Master-data mutation audit rows (same transaction as cache version bump).

use serde_json::Value;
use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::cache::versions::{bump_in_tx, Domain};
use crate::error::AppResult;

#[derive(Debug, Clone)]
pub struct AuditEvent {
    pub section: &'static str,
    pub entity_type: &'static str,
    pub entity_id: String,
    pub action: &'static str,
    pub actor_user_id: String,
    pub before: Option<Value>,
    pub after: Option<Value>,
}

pub async fn insert_in_tx(
    tx: &mut Transaction<'_, Postgres>,
    event: &AuditEvent,
) -> AppResult<()> {
    let actor = Uuid::parse_str(&event.actor_user_id).unwrap_or_else(|_| Uuid::nil());
    sqlx::query(
        r#"INSERT INTO master_data_audit
           (section, "entityType", "entityId", action, "actorUserId", "beforeJson", "afterJson")
           VALUES ($1,$2,$3,$4,$5,$6,$7)"#,
    )
    .bind(event.section)
    .bind(event.entity_type)
    .bind(&event.entity_id)
    .bind(event.action)
    .bind(actor)
    .bind(event.before.as_ref())
    .bind(event.after.as_ref())
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub async fn commit_with_audit(
    mut tx: Transaction<'_, Postgres>,
    event: AuditEvent,
    domain: Domain,
) -> AppResult<()> {
    insert_in_tx(&mut tx, &event).await?;
    bump_in_tx(&mut tx, domain).await?;
    tx.commit().await?;
    Ok(())
}

pub fn redact_secrets(mut value: Value) -> Value {
    if let Some(obj) = value.as_object_mut() {
        for key in [
            "password",
            "token",
            "secret",
            "apiKey",
            "razorpay",
            "otp",
        ] {
            if obj.contains_key(key) {
                obj.insert(key.into(), Value::String("[redacted]".into()));
            }
        }
    }
    value
}
