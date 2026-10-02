use serde_json::Value;
use sqlx::PgConnection;
use uuid::Uuid;

use crate::error::AppResult;

/// The caller must already hold `FOR UPDATE` on `businesses` (and on the hall
/// row when `hall_id` is set). This insert's foreign keys take a key-share
/// lock on those rows.
pub async fn write_audit(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    entity_type: &str,
    entity_id: &str,
    action: &str,
    actor: Uuid,
    payload: Value,
) -> AppResult<()> {
    sqlx::query(
        r#"INSERT INTO hall_audit_log
           (id, "businessId", "hallId", "entityType", "entityId", action, "actorUserId", payload)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"#,
    )
    .bind(Uuid::new_v4())
    .bind(business_id)
    .bind(hall_id)
    .bind(entity_type)
    .bind(entity_id)
    .bind(action)
    .bind(actor)
    .bind(payload)
    .execute(&mut *tx)
    .await?;
    Ok(())
}

pub async fn bump_hall_caches(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    business_id: Uuid,
    hall_id: Option<Uuid>,
) -> AppResult<()> {
    let biz_domain = format!("business:{}:halls", business_id);
    bump_domain(tx, &biz_domain).await?;
    if let Some(hid) = hall_id {
        let cal = format!("hall:{}:calendar", hid);
        bump_domain(tx, &cal).await?;
    }
    let enq = format!("business:{}:enquiries", business_id);
    bump_domain(tx, &enq).await?;
    Ok(())
}

async fn bump_domain(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    domain: &str,
) -> AppResult<()> {
    sqlx::query(
        r#"INSERT INTO cache_versions (domain, version) VALUES ($1, 1)
           ON CONFLICT (domain) DO UPDATE
           SET version = cache_versions.version + 1, "updatedAt" = NOW()"#,
    )
    .bind(domain)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
