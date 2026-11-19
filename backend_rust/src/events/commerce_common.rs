use super::*;
use sqlx::{Postgres, Transaction};

/// Locks the quote before its commerce rows, serializing both participants.
/// A missing/unauthorized quote intentionally returns the same 404 response.
pub(super) struct CommerceContext {
    pub(super) plan_id: Uuid,
    pub(super) customer_id: Uuid,
    pub(super) vendor_id: Uuid,
    pub(super) customer: bool,
    pub(super) service: String,
    pub(super) status: String,
    pub(super) cancelled: bool,
}

pub(super) async fn access(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
    user_id: Uuid,
    lock: bool,
) -> AppResult<CommerceContext> {
    let query = r#"SELECT q."planId",q.status::text AS status,
        q."serviceType"::text AS service,
        p."customerId",p."cancelledAt",b."ownerId"
        FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
        JOIN businesses b ON b.id=q."businessId"
        WHERE q.id=$1 AND (p."customerId"=$2 OR b."ownerId"=$2)"#;
    let sql = if lock { format!("{query} FOR UPDATE OF q") } else { query.to_owned() };
    let row = sqlx::query(&sql)
        .bind(quote_id).bind(user_id)
        .fetch_optional(&mut **tx).await?
        .ok_or_else(|| AppError::NotFound("Event quote not found".into()))?;
    let customer_id: Uuid = row.get("customerId");
    Ok(CommerceContext {
        plan_id: row.get("planId"),
        customer_id,
        vendor_id: row.get("ownerId"),
        customer: customer_id == user_id,
        service: row.get("service"),
        status: row.get("status"),
        cancelled: row.get::<Option<DateTime<Utc>>, _>("cancelledAt").is_some(),
    })
}

pub(super) fn active(context: &CommerceContext) -> AppResult<()> {
    if context.status != "CONFIRMED" || context.cancelled {
        return Err(AppError::Conflict("This action requires a confirmed, active quote".into()));
    }
    Ok(())
}

pub(super) async fn milestone(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
    milestone_id: Uuid,
    kind: &str,
) -> AppResult<sqlx::postgres::PgRow> {
    let row = sqlx::query(
        r#"SELECT id,kind,amount,"completedAt" FROM event_quote_milestones
           WHERE id=$1 AND "quoteId"=$2 AND kind=$3 FOR UPDATE"#,
    )
    .bind(milestone_id).bind(quote_id).bind(kind)
    .fetch_optional(&mut **tx).await?
    .ok_or_else(|| AppError::NotFound("Milestone not found".into()))?;
    Ok(row)
}

pub(super) async fn notify_other(
    tx: &mut Transaction<'_, Postgres>,
    context: &CommerceContext,
    title: &str,
    message: &str,
) -> AppResult<()> {
    crate::outbox::notify(
        tx, context.plan_id,
        if context.customer { context.vendor_id } else { context.customer_id },
        title, message,
        json!({"type":"event_update","planId":context.plan_id}),
    ).await
}

pub(super) fn validate_text(value: &str, min: usize, max: usize) -> AppResult<String> {
    let trimmed = value.trim();
    if trimmed.len() < min || trimmed.len() > max {
        return Err(AppError::BadRequest(format!(
            "Enter between {min} and {max} characters"
        )));
    }
    Ok(trimmed.to_owned())
}

/// Update both roles' milestone acknowledgements only after the participant
/// workflow provides its stronger proof/approval checks.
pub(super) async fn complete_milestone(
    tx: &mut Transaction<'_, Postgres>,
    milestone_id: Uuid,
    customer: Uuid,
    vendor: Uuid,
) -> AppResult<()> {
    sqlx::query(
        r#"UPDATE event_quote_milestones SET
           "customerAcknowledgedAt"=COALESCE("customerAcknowledgedAt",NOW()),
           "vendorAcknowledgedAt"=COALESCE("vendorAcknowledgedAt",NOW()),
           "completedAt"=COALESCE("completedAt",NOW()),"updatedAt"=NOW()
           WHERE id=$1"#,
    ).bind(milestone_id).execute(&mut **tx).await?;
    for (actor, action) in [
        (customer, "CUSTOMER_ACKNOWLEDGED"),
        (vendor, "VENDOR_ACKNOWLEDGED"),
    ] {
        sqlx::query(
            r#"INSERT INTO event_quote_milestone_events
               (id,"milestoneId","actorId",action)
               VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING"#,
        )
        .bind(Uuid::new_v4()).bind(milestone_id).bind(actor).bind(action)
        .execute(&mut **tx).await?;
    }
    Ok(())
}
