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

/// Lock order: venue row → halls ORDER BY id → then child checks.
/// `hall_ids`: None = lock all halls for the business (venue-wide / legacy).
pub async fn acquire_hall_scope_locks(
    tx: &mut PgConnection,
    business_id: Uuid,
    hall_ids: Option<&[Uuid]>,
) -> AppResult<()> {
    // Ensure venue exists so FOR UPDATE has a row.
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
    // Legacy offlineDays until fully migrated.
    let offline = sqlx::query(
        r#"SELECT "offlineDays"::jsonb AS offline FROM businesses WHERE id = $1"#,
    )
    .bind(business_id)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(row) = offline {
        let offset = chrono::FixedOffset::east_opt(19800).unwrap();
        let first = interval.start.with_timezone(&offset).date_naive();
        let last = (interval.end - chrono::Duration::milliseconds(1))
            .with_timezone(&offset)
            .date_naive();
        if row
            .try_get::<Option<serde_json::Value>, _>("offline")
            .ok()
            .flatten()
            .and_then(|v| v.as_array().cloned())
            .unwrap_or_default()
            .iter()
            .any(|v| {
                v.as_str()
                    .and_then(|s| s.get(..10))
                    .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                    .is_some_and(|d| d >= first && d <= last)
            })
        {
            return Err(AppError::Conflict(
                "The business is unavailable on an event day".into(),
            ));
        }
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
