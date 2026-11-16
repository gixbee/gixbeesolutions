use super::*;
use chrono::Duration;
use sqlx::{Postgres, Transaction};

/// Direct-payment and deliverable milestones belong to a confirmed quote.
/// No endpoint in this module charges a card or transfers funds.
pub(super) fn routes() -> Router<AppState> {
    Router::new()
        .route("/quotes/{id}/milestones", get(list).post(create))
        .route("/quotes/{id}/milestones/{milestone_id}/ack", post(acknowledge))
}

#[derive(Debug)]
struct QuoteContext {
    id: Uuid,
    plan_id: Uuid,
    customer_id: Uuid,
    vendor_id: Uuid,
    customer: bool,
    service: String,
    status: String,
    amount: Decimal,
    request: Option<Value>,
    starts_at: DateTime<Utc>,
    cancelled: bool,
}

fn quote_from_row(row: &sqlx::postgres::PgRow, uid: Uuid) -> QuoteContext {
    let customer_id: Uuid = row.get("customerId");
    QuoteContext {
        id: row.get("id"),
        plan_id: row.get("planId"),
        customer_id,
        vendor_id: row.get("ownerId"),
        customer: customer_id == uid,
        service: row.get("service"),
        status: row.get("status"),
        amount: row.get("amount"),
        request: row.try_get("serviceRequest").ok().flatten(),
        starts_at: row.get("startTime"),
        cancelled: row.get::<Option<DateTime<Utc>>, _>("cancelledAt").is_some(),
    }
}

const QUOTE_ACCESS: &str = r#"SELECT q.id, q."planId", q.status::text AS status,
       q."serviceType"::text AS service, q.amount,
       p."customerId", p."serviceRequest", p."startTime", p."cancelledAt",
       b."ownerId"
    FROM event_quotes q
    JOIN event_plans p ON p.id = q."planId"
    JOIN businesses b ON b.id = q."businessId"
    WHERE q.id = $1 AND (p."customerId" = $2 OR b."ownerId" = $2)"#;

async fn access(db: &sqlx::PgPool, quote_id: Uuid, uid: Uuid) -> AppResult<QuoteContext> {
    let row = sqlx::query(QUOTE_ACCESS)
        .bind(quote_id)
        .bind(uid)
        .fetch_optional(db)
        .await?
        .ok_or_else(|| AppError::NotFound("Event quote not found".into()))?;
    Ok(quote_from_row(&row, uid))
}

async fn locked_access(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
    uid: Uuid,
) -> AppResult<QuoteContext> {
    // Locks quote before milestone rows. No participant can confirm a
    // milestone against an concurrently cancelled or revised quote.
    let sql = format!("{QUOTE_ACCESS} FOR UPDATE OF q");
    let row = sqlx::query(&sql)
        .bind(quote_id)
        .bind(uid)
        .fetch_optional(&mut **tx)
        .await?
        .ok_or_else(|| AppError::NotFound("Event quote not found".into()))?;
    Ok(quote_from_row(&row, uid))
}

async fn rows(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
) -> AppResult<Vec<Value>> {
    Ok(sqlx::query_scalar::<_, Value>(
        r#"SELECT to_jsonb(m) || jsonb_build_object('overdue',
                   m."dueAt" IS NOT NULL AND m."dueAt" < NOW()
                   AND m."completedAt" IS NULL)
           FROM event_quote_milestones m
           WHERE m."quoteId"=$1
           ORDER BY CASE WHEN m.kind='PAYMENT' THEN 0 ELSE 1 END,
                    m."position""#,
    )
    .bind(quote_id)
    .fetch_all(&mut **tx)
    .await?)
}

pub(super) async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    access(&state.db, id, uid).await?;
    let rows = sqlx::query_scalar::<_, Value>(
        r#"SELECT to_jsonb(m) || jsonb_build_object('overdue',
                   m."dueAt" IS NOT NULL AND m."dueAt" < NOW()
                   AND m."completedAt" IS NULL)
           FROM event_quote_milestones m
           WHERE m."quoteId"=$1 AND EXISTS (
             SELECT 1 FROM event_quotes q
             JOIN event_plans p ON p.id=q."planId"
             JOIN businesses b ON b.id=q."businessId"
             WHERE q.id=m."quoteId" AND (p."customerId"=$2 OR b."ownerId"=$2)
           )
           ORDER BY CASE WHEN m.kind='PAYMENT' THEN 0 ELSE 1 END, m."position""#,
    )
    .bind(id)
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MilestoneInput {
    kind: String,
    label: String,
    #[serde(default)]
    details: String,
    percent: Option<i32>,
    due_at: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScheduleInput {
    milestones: Vec<MilestoneInput>,
}

#[derive(Clone)]
struct MilestoneSeed {
    kind: &'static str,
    position: i16,
    label: String,
    details: String,
    percent: Option<i16>,
    amount: Option<Decimal>,
    due_at: Option<DateTime<Utc>>,
}

fn distribute_payments(
    total: Decimal,
    parts: &[(String, i16, Option<DateTime<Utc>>)],
) -> AppResult<Vec<MilestoneSeed>> {
    if parts.is_empty()
        || parts.len() > 12
        || parts.iter().map(|(_, pct, _)| i32::from(*pct)).sum::<i32>() != 100
    {
        return Err(AppError::BadRequest("Payment percentages must total 100".into()));
    }
    let mut remaining = total;
    let mut rows = Vec::with_capacity(parts.len());
    for (idx, (label, pct, due)) in parts.iter().enumerate() {
        if !(1..=100).contains(pct) || label.trim().is_empty() || label.len() > 150 {
            return Err(AppError::BadRequest("Check milestone payment labels".into()));
        }
        let amount = if idx + 1 == parts.len() {
            remaining
        } else {
            (total * Decimal::from(*pct) / Decimal::from(100)).round_dp(2)
        };
        if amount <= Decimal::ZERO {
            return Err(AppError::BadRequest(
                "Payment milestones must have a positive amount".into(),
            ));
        }
        remaining -= amount;
        rows.push(MilestoneSeed {
            kind: "PAYMENT",
            position: (idx + 1) as i16,
            label: label.trim().to_string(),
            details: "Direct payment to the vendor; both parties must acknowledge it".into(),
            percent: Some(*pct),
            amount: Some(amount),
            due_at: due.clone(),
        });
    }
    Ok(rows)
}

fn validate_manual(input: ScheduleInput, context: &QuoteContext) -> AppResult<Vec<MilestoneSeed>> {
    if input.milestones.is_empty() || input.milestones.len() > 20 {
        return Err(AppError::BadRequest("Choose 1–20 milestones".into()));
    }
    let mut payment_parts = Vec::new();
    let mut delivery = Vec::new();
    for entry in input.milestones {
        let label = entry.label.trim();
        if label.is_empty() || label.len() > 150 || entry.details.len() > 3000 {
            return Err(AppError::BadRequest("Check milestone labels and details".into()));
        }
        let due = entry.due_at.as_deref().map(parse_time).transpose()?;
        match entry.kind.as_str() {
            "PAYMENT" => {
                let pct = entry.percent.ok_or_else(|| {
                    AppError::BadRequest("Payment milestone requires a percentage".into())
                })?;
                if !(1..=100).contains(&pct) {
                    return Err(AppError::BadRequest("Payment percentage must be 1–100".into()));
                }
                payment_parts.push((label.to_string(), pct as i16, due));
            }
            "DELIVERY" if entry.percent.is_none() => {
                if delivery.len() >= 12 {
                    return Err(AppError::BadRequest("Too many deliverables".into()));
                }
                delivery.push(MilestoneSeed {
                    kind: "DELIVERY",
                    position: (delivery.len() + 1) as i16,
                    label: label.to_string(),
                    details: entry.details.trim().to_string(),
                    percent: None,
                    amount: None,
                    due_at: due,
                });
            }
            _ => return Err(AppError::BadRequest("Invalid milestone type".into())),
        }
    }
    let mut rows = if payment_parts.is_empty() {
        Vec::new()
    } else {
        distribute_payments(context.amount, &payment_parts)?
    };
    rows.extend(delivery);
    Ok(rows)
}

async fn insert_rows(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
    milestones: &[MilestoneSeed],
) -> AppResult<()> {
    for entry in milestones {
        sqlx::query(
            r#"INSERT INTO event_quote_milestones
               (id,"quoteId",kind,"position",label,details,"percent",amount,"dueAt")
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)"#,
        )
        .bind(Uuid::new_v4())
        .bind(quote_id)
        .bind(entry.kind)
        .bind(entry.position)
        .bind(&entry.label)
        .bind(&entry.details)
        .bind(entry.percent)
        .bind(entry.amount)
        .bind(entry.due_at.clone())
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}

pub(super) async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
    Json(body): Json<ScheduleInput>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = locked_access(&mut tx, id, uid).await?;
    if context.customer {
        return Err(AppError::Forbidden("Only the vendor can create a milestone schedule".into()));
    }
    if context.status != "CONFIRMED" || context.cancelled {
        return Err(AppError::Conflict("Confirm the quote before setting milestones".into()));
    }
    let existing: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quote_milestones WHERE "quoteId"=$1)"#,
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if existing {
        return Err(AppError::Conflict(
            "A schedule already exists. Milestones are immutable after publication".into(),
        ));
    }
    let planned = validate_manual(body, &context)?;
    insert_rows(&mut tx, id, &planned).await?;
    crate::outbox::notify(
        &mut tx,
        context.plan_id,
        context.customer_id,
        "Event milestone schedule",
        "Your vendor published payment or delivery milestones. Review the agreed terms.",
        json!({"type":"event_update","planId":context.plan_id}),
    )
    .await?;
    let result = rows(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(result))
}

pub(super) async fn acknowledge(
    State(state): State<AppState>,
    user: AuthUser,
    Path((id, milestone_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let context = locked_access(&mut tx, id, uid).await?;
    if context.status != "CONFIRMED" || context.cancelled {
        return Err(AppError::Conflict(
            "Milestones can only be acknowledged for a confirmed booking".into(),
        ));
    }
    let milestone = sqlx::query(
        r#"SELECT id,kind,"completedAt","customerAcknowledgedAt","vendorAcknowledgedAt"
           FROM event_quote_milestones WHERE id=$1 AND "quoteId"=$2 FOR UPDATE"#,
    )
    .bind(milestone_id)
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Milestone not found".into()))?;

    let own_column = if context.customer { "customerAcknowledgedAt" } else { "vendorAcknowledgedAt" };
    let other_column = if context.customer { "vendorAcknowledgedAt" } else { "customerAcknowledgedAt" };
    let already: Option<DateTime<Utc>> = milestone.get(own_column);
    if already.is_none() {
        // These identifiers come only from the two static branches above.
        sqlx::query(&format!(
            r#"UPDATE event_quote_milestones
               SET "{own_column}"=NOW(),
                   "completedAt"=CASE WHEN "{other_column}" IS NOT NULL
                       THEN NOW() ELSE "completedAt" END,
                   "updatedAt"=NOW()
               WHERE id=$1"#
        ))
        .bind(milestone_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"INSERT INTO event_quote_milestone_events
               (id,"milestoneId","actorId",action)
               VALUES ($1,$2,$3,$4) ON CONFLICT DO NOTHING"#,
        )
        .bind(Uuid::new_v4())
        .bind(milestone_id)
        .bind(uid)
        .bind(if context.customer {
            "CUSTOMER_ACKNOWLEDGED"
        } else {
            "VENDOR_ACKNOWLEDGED"
        })
        .execute(&mut *tx)
        .await?;

        crate::outbox::notify(
            &mut tx,
            context.plan_id,
            if context.customer { context.vendor_id } else { context.customer_id },
            "Event milestone acknowledged",
            if context.customer {
                "The customer acknowledged a direct payment or deliverable."
            } else {
                "The vendor acknowledged a direct payment or deliverable."
            },
            json!({"type":"event_update","planId":context.plan_id}),
        )
        .await?;
    }
    let item: Value = sqlx::query_scalar(
        r#"SELECT to_jsonb(m) || jsonb_build_object('overdue',
                   m."dueAt" IS NOT NULL AND m."dueAt" < NOW()
                   AND m."completedAt" IS NULL)
           FROM event_quote_milestones m WHERE id=$1"#,
    )
    .bind(milestone_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(item))
}

/// Seed legacy-compatible milestones from the selected catalogue item or the
/// immutable hall package snapshot, in the SAME transaction as quote acceptance.
/// No extra network calls, cash transfer or new booking status is introduced.
pub(super) async fn seed_at_acceptance(
    tx: &mut Transaction<'_, Postgres>,
    quote_id: Uuid,
    service: &str,
    plan: &sqlx::postgres::PgRow,
    amount: Decimal,
) -> AppResult<()> {
    let exists: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quote_milestones WHERE "quoteId"=$1)"#,
    )
    .bind(quote_id)
    .fetch_one(&mut **tx)
    .await?;
    if exists { return Ok(()); }

    let mut milestones = Vec::new();
    if service == "PHOTOGRAPHY" {
        let request: Option<Value> = plan.try_get("serviceRequest").ok().flatten();
        let item = request.as_ref()
            .and_then(|v| v["items"].as_array())
            .and_then(|a| a.first())
            .and_then(|v| v.get("item"));
        if let Some(item) = item {
            if let Some(stages) = item["paymentSplit"].as_array() {
                let parts = stages.iter().filter_map(|stage| {
                    let label = stage["label"].as_str()?;
                    let pct = stage["percent"].as_i64()?;
                    if !(1..=100).contains(&pct) { return None; }
                    Some((label.to_string(), pct as i16, None))
                }).collect::<Vec<_>>();
                // An older catalogue may have malformed stage metadata.
                // Never invalidate a customer acceptance due to old metadata.
                if parts.len() == stages.len() {
                    if let Ok(rows) = distribute_payments(amount, &parts) {
                        milestones.extend(rows);
                    }
                }
            }
            if let Some(delivery) = item["delivery"].as_str().filter(|s| !s.trim().is_empty()) {
                milestones.push(MilestoneSeed {
                    kind: "DELIVERY",
                    position: 1,
                    label: "Deliver photography photos, videos and albums".into(),
                    details: delivery.chars().take(3000).collect(),
                    percent: None,
                    amount: None,
                    due_at: None,
                });
            }
        }
    } else if service == "HALL" {
        let terms: Option<Value> = sqlx::query_scalar(
            r#"SELECT terms FROM hall_booking_terms_snapshot
               WHERE "quoteId"=$1 ORDER BY "createdAt" DESC LIMIT 1"#,
        )
        .bind(quote_id)
        .fetch_optional(&mut **tx)
        .await?
        .flatten();
        if let Some(terms) = terms {
            let policy = &terms["payment"];
            let advance_type = policy["advanceType"].as_str().unwrap_or("fixed");
            let percent = if advance_type == "percent" {
                policy["advancePct"].as_i64().filter(|pct| (1..=100).contains(pct))
            } else {
                None
            };
            let value = if let Some(pct) = percent {
                (amount * Decimal::from(pct) / Decimal::from(100)).round_dp(2)
            } else {
                Decimal::from(policy["advanceFixed"].as_i64().unwrap_or(0))
            };
            if value > Decimal::ZERO && value <= amount {
                let proposed_due = Utc::now() + Duration::hours(24);
                let starts_at: DateTime<Utc> = plan.get("startTime");
                let due_at = if proposed_due > starts_at { starts_at } else { proposed_due };
                milestones.push(MilestoneSeed {
                    kind: "PAYMENT",
                    position: 1,
                    label: "Hall advance paid directly to owner".into(),
                    details: "Direct payment only. Both parties must acknowledge receipt before it is marked complete. The deadline is informational and does not automatically cancel the booking.".into(),
                    percent: percent.map(|p| p as i16),
                    amount: Some(value),
                    due_at: Some(due_at),
                });
            }
        }
    }
    insert_rows(tx, quote_id, &milestones).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payment_rounding_preserves_quote_total() {
        let rows = distribute_payments(
            Decimal::from(999),
            &[("Deposit".into(), 33, None), ("Balance".into(), 67, None)],
        ).unwrap();
        assert_eq!(rows.iter().map(|v| v.amount.unwrap()).sum::<Decimal>(), Decimal::from(999));
    }

    #[test]
    fn payment_percent_must_total_100() {
        let value = distribute_payments(
            Decimal::from(1000),
            &[("Deposit".into(), 30, None), ("Balance".into(), 50, None)],
        );
        assert!(value.is_err());
    }

    #[test]
    fn tiny_quote_cannot_create_zero_rupee_milestone() {
        let value = distribute_payments(
            Decimal::new(1, 2),
            &[("First".into(), 1, None), ("Rest".into(), 99, None)],
        );
        assert!(value.is_err());
    }
}
