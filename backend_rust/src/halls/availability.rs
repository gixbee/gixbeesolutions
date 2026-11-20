use chrono::{DateTime, Utc};
use sqlx::{PgConnection, Row};
use uuid::Uuid;

use crate::error::{AppError, AppResult};

#[derive(Debug, Clone, Copy)]
pub struct Interval {
    pub start: DateTime<Utc>,
    pub end: DateTime<Utc>,
}

impl Interval {
    pub fn new(start: DateTime<Utc>, end: DateTime<Utc>) -> AppResult<Self> {
        if end <= start {
            return Err(AppError::BadRequest(
                "Interval end must be after start".into(),
            ));
        }
        Ok(Self { start, end })
    }
}

/// Lock `businesses` rows in ascending id order.
///
/// Event-scoped work locks `event_plans` before this. Venue and hall locks come
/// after it. Inserts into `hall_audit_log`, `hall_reservations`, and
/// `hall_enquiries` take a key-share lock on `businesses` through their foreign
/// keys, and that conflicts with `FOR UPDATE`, so the business row must already
/// be held here.
pub async fn lock_business_rows(
    tx: &mut PgConnection,
    business_ids: &[Uuid],
) -> AppResult<()> {
    if business_ids.is_empty() {
        return Ok(());
    }
    let mut sorted = business_ids.to_vec();
    sorted.sort();
    sorted.dedup();
    let rows = sqlx::query(r#"SELECT id FROM businesses WHERE id = ANY($1) ORDER BY id FOR UPDATE"#)
        .bind(&sorted)
        .fetch_all(&mut *tx)
        .await?;
    if rows.len() != sorted.len() {
        return Err(AppError::NotFound("Business not found".into()));
    }
    Ok(())
}

/// Lock order for one business: `businesses` → venue → halls ORDER BY id.
///
/// Event-scoped callers lock the parent `event_plans` row before this helper.
/// When several businesses are involved, lock every business with
/// [`lock_business_rows`] first, then call this helper for each id in that same
/// order. `hall_ids`: None = all active halls. An empty slice locks the business
/// and venue only.
pub async fn acquire_hall_scope_locks(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_ids: Option<&[Uuid]>,
) -> AppResult<()> {
    lock_business_rows(tx, &[business_id]).await?;
    // Ensure venue exists so FOR UPDATE has a row. The business row is already
    // locked, so this insert's foreign key does not wait.
    sqlx::query(
        r#"INSERT INTO business_hall_venue ("businessId") VALUES ($1)
           ON CONFLICT ("businessId") DO NOTHING"#,
    )
    .bind(business_id)
    .execute(&mut *tx)
    .await?;

    sqlx::query(
        r#"SELECT "businessId" FROM business_hall_venue
           WHERE "businessId" = $1 FOR UPDATE"#,
    )
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;

    match hall_ids {
        None => {
            sqlx::query(
                r#"SELECT id FROM business_halls
                   WHERE "businessId" = $1 AND "archivedAt" IS NULL
                   ORDER BY id FOR UPDATE"#,
            )
            .bind(business_id)
            .fetch_all(&mut *tx)
            .await?;
        }
        Some(ids) if ids.is_empty() => {}
        Some(ids) => {
            let mut sorted = ids.to_vec();
            sorted.sort();
            sqlx::query(
                r#"SELECT id FROM business_halls
                   WHERE "businessId" = $1 AND id = ANY($2)
                   ORDER BY id FOR UPDATE"#,
            )
            .bind(business_id)
            .bind(&sorted)
            .fetch_all(&mut *tx)
            .await?;
        }
    }
    Ok(())
}

/// Unified availability. `exclude_reservation_id` skips that hold (accept promote).
pub async fn availability_check(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    interval: Interval,
    exclude_reservation_id: Option<Uuid>,
) -> AppResult<()> {
    if let Some(hid) = hall_id {
        check_hall_path(
            tx,
            business_id,
            hid,
            interval,
            exclude_reservation_id,
        )
        .await?;
    } else {
        check_legacy_path(tx, business_id, interval, exclude_reservation_id).await?;
    }
    Ok(())
}

async fn reservation_blocks(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    interval: Interval,
    exclude_reservation_id: Option<Uuid>,
) -> AppResult<bool> {
    // HELD only while expiresAt > NOW(); CONFIRMED always blocks.
    let blocked: bool = if let Some(hid) = hall_id {
        sqlx::query_scalar(
            r#"SELECT EXISTS(
                SELECT 1 FROM hall_reservations r
                WHERE r."businessId" = $1 AND r."hallId" = $2
                  AND r."startAt" < $4 AND r."endAt" > $3
                  AND ($5::uuid IS NULL OR r.id <> $5)
                  AND (
                    r.status = 'CONFIRMED'
                    OR (r.status = 'HELD' AND r."expiresAt" > NOW())
                  )
            )"#,
        )
        .bind(business_id)
        .bind(hid)
        .bind(interval.start)
        .bind(interval.end)
        .bind(exclude_reservation_id)
        .fetch_one(&mut *tx)
        .await?
    } else {
        sqlx::query_scalar(
            r#"SELECT EXISTS(
                SELECT 1 FROM hall_reservations r
                WHERE r."businessId" = $1
                  AND r."startAt" < $3 AND r."endAt" > $2
                  AND ($4::uuid IS NULL OR r.id <> $4)
                  AND (
                    r.status = 'CONFIRMED'
                    OR (r.status = 'HELD' AND r."expiresAt" > NOW())
                  )
            )"#,
        )
        .bind(business_id)
        .bind(interval.start)
        .bind(interval.end)
        .bind(exclude_reservation_id)
        .fetch_one(&mut *tx)
        .await?
    };
    Ok(blocked)
}

async fn active_blocks_overlap(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    include_venue_wide: bool,
    include_any_hall: bool,
    interval: Interval,
) -> AppResult<bool> {
    let blocked: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM hall_calendar_blocks b
            WHERE b."businessId" = $1
              AND b."releasedAt" IS NULL
              AND b."startAt" < $3 AND b."endAt" > $2
              AND (
                ($4::uuid IS NOT NULL AND b."hallId" = $4)
                OR ($5 AND b."hallId" IS NULL)
                OR ($6 AND b."hallId" IS NOT NULL)
              )
        )"#,
    )
    .bind(business_id)
    .bind(interval.start)
    .bind(interval.end)
    .bind(hall_id)
    .bind(include_venue_wide)
    .bind(include_any_hall)
    .fetch_one(&mut *tx)
    .await?;
    Ok(blocked)
}

async fn legacy_null_hall_quotes_overlap(
    tx: &mut PgConnection,
    business_id: Uuid,
    interval: Interval,
) -> AppResult<bool> {
    let blocked: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM event_quotes q
            JOIN event_plans p ON p.id = q."planId"
            WHERE q."businessId" = $1
              AND q."serviceType" = 'HALL'
              AND q."hallId" IS NULL
              AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
              AND p."startTime" < $3 AND p."endTime" > $2
        )"#,
    )
    .bind(business_id)
    .bind(interval.start)
    .bind(interval.end)
    .fetch_one(&mut *tx)
    .await?;
    Ok(blocked)
}

async fn check_hall_path(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_id: Uuid,
    interval: Interval,
    exclude_reservation_id: Option<Uuid>,
) -> AppResult<()> {
    if reservation_blocks(
        tx,
        business_id,
        Some(hall_id),
        interval,
        exclude_reservation_id,
    )
    .await?
    {
        return Err(AppError::Conflict(
            "This hall already has a booking or hold in that time window".into(),
        ));
    }
    if active_blocks_overlap(tx, business_id, Some(hall_id), true, false, interval).await? {
        return Err(AppError::Conflict(
            "This hall or venue is blocked in that time window".into(),
        ));
    }
    if legacy_null_hall_quotes_overlap(tx, business_id, interval).await? {
        return Err(AppError::Conflict(
            "The business has a legacy hall booking covering that time".into(),
        ));
    }
    Ok(())
}

async fn check_legacy_path(
    tx: &mut PgConnection,
    business_id: Uuid,
    interval: Interval,
    exclude_reservation_id: Option<Uuid>,
) -> AppResult<()> {
    if reservation_blocks(tx, business_id, None, interval, exclude_reservation_id).await? {
        return Err(AppError::Conflict(
            "A hall under this business is already reserved in that time window".into(),
        ));
    }
    // Venue-wide + any hall-specific block.
    if active_blocks_overlap(tx, business_id, None, true, true, interval).await? {
        return Err(AppError::Conflict(
            "The venue has a calendar block in that time window".into(),
        ));
    }
    // Existing business-wide confirmed quotes (any hallId including null).
    let quote_conflict: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM event_quotes q
            JOIN event_plans p ON p.id = q."planId"
            WHERE q."businessId" = $1
              AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
              AND p."startTime" < $3 AND p."endTime" > $2
        )"#,
    )
    .bind(business_id)
    .bind(interval.start)
    .bind(interval.end)
    .fetch_one(&mut *tx)
    .await?;
    if quote_conflict {
        return Err(AppError::Conflict(
            "The business has another event at this time".into(),
        ));
    }
    Ok(())
}

pub async fn release_reservation(
    tx: &mut PgConnection,
    reservation_id: Uuid,
) -> AppResult<()> {
    sqlx::query(
        r#"UPDATE hall_reservations
           SET status = 'RELEASED', "releasedAt" = NOW(), "updatedAt" = NOW()
           WHERE id = $1 AND status IN ('HELD','CONFIRMED')"#,
    )
    .bind(reservation_id)
    .execute(&mut *tx)
    .await?;
    Ok(())
}

pub async fn release_holds_for_quote(
    tx: &mut PgConnection,
    quote_id: Uuid,
) -> AppResult<()> {
    sqlx::query(
        r#"UPDATE hall_reservations
           SET status = 'RELEASED', "releasedAt" = NOW(), "updatedAt" = NOW()
           WHERE "quoteId" = $1 AND status = 'HELD'"#,
    )
    .bind(quote_id)
    .execute(&mut *tx)
    .await?;
    Ok(())
}

pub async fn release_holds_for_enquiry(
    tx: &mut PgConnection,
    enquiry_id: Uuid,
) -> AppResult<()> {
    sqlx::query(
        r#"UPDATE hall_reservations
           SET status = 'RELEASED', "releasedAt" = NOW(), "updatedAt" = NOW()
           WHERE "enquiryId" = $1 AND status IN ('HELD','CONFIRMED')"#,
    )
    .bind(enquiry_id)
    .execute(&mut *tx)
    .await?;
    Ok(())
}

/// Release active assignment and quote holds for one event. `CONFIRMED` rows stay.
/// Rows already `RELEASED` are left unchanged, so a repeat call writes nothing.
pub async fn release_held_for_plan(
    tx: &mut PgConnection,
    plan_id: Uuid,
) -> AppResult<Vec<sqlx::postgres::PgRow>> {
    let rows = sqlx::query(
        r#"UPDATE hall_reservations
           SET status = 'RELEASED', "releasedAt" = NOW(), "updatedAt" = NOW()
           WHERE status = 'HELD'
             AND (
               "enquiryId" IN (SELECT id FROM hall_enquiries WHERE "eventPlanId" = $1)
               OR "quoteId" IN (SELECT id FROM event_quotes WHERE "planId" = $1)
             )
           RETURNING id, "businessId", "hallId""#,
    )
    .bind(plan_id)
    .fetch_all(&mut *tx)
    .await?;
    Ok(rows)
}

pub fn assign_hold_expires_at(
    now: DateTime<Utc>,
    proposed_start: DateTime<Utc>,
    hold_hours: i64,
) -> DateTime<Utc> {
    let ttl_end = now + chrono::Duration::hours(hold_hours.max(1));
    if ttl_end < proposed_start {
        ttl_end
    } else {
        // Cap at booking start; if start already passed, expire immediately (1s).
        if proposed_start > now {
            proposed_start
        } else {
            now + chrono::Duration::seconds(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hold_ttl_caps_at_start() {
        let now = Utc::now();
        let start = now + chrono::Duration::hours(24);
        let exp = assign_hold_expires_at(now, start, 72);
        assert_eq!(exp, start);
    }

    #[test]
    fn hold_ttl_uses_hours_when_shorter() {
        let now = Utc::now();
        let start = now + chrono::Duration::hours(200);
        let exp = assign_hold_expires_at(now, start, 72);
        assert_eq!(exp, now + chrono::Duration::hours(72));
    }
}
