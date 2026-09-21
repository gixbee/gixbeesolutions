use chrono::{DateTime, Utc};
use rust_decimal::Decimal;

use crate::error::{AppError, AppResult};

pub fn parse_window(
    start: &str,
    end: &str,
    now: DateTime<Utc>,
) -> AppResult<(DateTime<Utc>, DateTime<Utc>)> {
    let parse = |value: &str| {
        DateTime::parse_from_rfc3339(value)
            .map(|d| d.with_timezone(&Utc))
            .map_err(|_| {
                AppError::BadRequest(
                    "Rental times must include a valid date, time and timezone".into(),
                )
            })
    };
    let start = parse(start)?;
    let end = parse(end)?;
    if end <= start {
        return Err(AppError::BadRequest(
            "End time must be after start time".into(),
        ));
    }
    if start < now - chrono::Duration::minutes(1) {
        return Err(AppError::BadRequest(
            "Start time cannot be in the past".into(),
        ));
    }
    if end - start > chrono::Duration::days(366) {
        return Err(AppError::BadRequest(
            "Rentals cannot exceed 366 days".into(),
        ));
    }
    Ok((start, end))
}

pub fn price(
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    hourly: Decimal,
    daily: Option<Decimal>,
    minimum_hours: i32,
) -> AppResult<Decimal> {
    let milliseconds = (end - start).num_milliseconds();
    if milliseconds <= 0
        || hourly < Decimal::ZERO
        || daily.is_some_and(|r| r <= Decimal::ZERO)
        || minimum_hours < 1
    {
        return Err(AppError::BadRequest(
            "Invalid rental duration or pricing".into(),
        ));
    }
    if milliseconds < i64::from(minimum_hours) * 3_600_000 {
        return Err(AppError::BadRequest(format!(
            "Minimum rental period is {minimum_hours} hours"
        )));
    }
    let amount = if let Some(rate) = daily.filter(|_| milliseconds >= 86_400_000) {
        rate * Decimal::from((milliseconds + 86_399_999) / 86_400_000)
    } else {
        hourly * Decimal::from(milliseconds) / Decimal::from(3_600_000)
    };
    if amount <= Decimal::ZERO || amount > Decimal::from(99_999_999) {
        return Err(AppError::BadRequest(
            "Rental total is outside the supported range".into(),
        ));
    }
    Ok(amount.round_dp(2))
}

pub fn transition(current: &str, next: &str, is_owner: bool, is_renter: bool) -> AppResult<()> {
    let authorized = if next == "CANCELLED" {
        is_renter
    } else {
        is_owner
    };
    if !authorized {
        return Err(AppError::Forbidden(
            "You cannot perform this rental action".into(),
        ));
    }
    let valid = matches!(
        (current, next),
        ("PENDING" | "PENDING_OWNER_CONFIRMATION", "CONFIRMED" | "REJECTED" | "CANCELLED")
            | ("TEMP_HOLD" | "PAYMENT_PENDING", "CANCELLED" | "REJECTED")
            | ("CONFIRMED", "ACTIVE" | "CANCELLED")
            | ("ACTIVE", "COMPLETED" | "RETURN_PENDING")
            | ("RETURN_PENDING", "COMPLETED")
    );
    if !valid {
        return Err(AppError::Conflict(format!(
            "Cannot change rental from {current} to {next}"
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multi_day_and_partial_hour_totals_use_the_whole_interval() {
        let start = DateTime::parse_from_rfc3339("2026-10-01T09:00:00+05:30")
            .unwrap()
            .with_timezone(&Utc);
        assert_eq!(
            price(
                start,
                start + chrono::Duration::days(3),
                Decimal::from(100),
                Some(Decimal::from(800)),
                1
            )
            .unwrap(),
            Decimal::from(2400)
        );
        assert_eq!(
            price(
                start,
                start + chrono::Duration::hours(25),
                Decimal::from(100),
                Some(Decimal::from(800)),
                1
            )
            .unwrap(),
            Decimal::from(1600)
        );
        assert_eq!(
            price(
                start,
                start + chrono::Duration::minutes(90),
                Decimal::from(101),
                None,
                1
            )
            .unwrap(),
            Decimal::new(15150, 2)
        );
        assert!(price(
            start,
            start + chrono::Duration::hours(2),
            Decimal::from(100),
            None,
            4
        )
        .is_err());
    }

    #[test]
    fn times_are_validated_before_any_reservation_is_created() {
        let now = DateTime::parse_from_rfc3339("2026-10-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        assert!(parse_window("2026-10-01T12:00:00", "2026-10-01T13:00:00", now).is_err());
        assert!(parse_window("2026-09-01T12:00:00Z", "2026-10-01T13:00:00Z", now).is_err());
        assert!(parse_window("2026-10-01T12:00:00Z", "2026-10-01T12:00:00Z", now).is_err());
        let (start, _) = parse_window(
            "2026-10-01T10:00:00+05:30",
            "2026-10-01T12:00:00+05:30",
            now,
        )
        .unwrap();
        assert_eq!(start.to_rfc3339(), "2026-10-01T04:30:00+00:00");
    }

    #[test]
    fn participants_cannot_skip_or_reverse_fulfillment() {
        assert!(transition("PENDING", "CONFIRMED", false, true).is_err());
        assert!(transition("PENDING", "CONFIRMED", true, false).is_ok());
        assert!(transition("CONFIRMED", "COMPLETED", true, false).is_err());
        assert!(transition("ACTIVE", "CANCELLED", false, true).is_err());
        assert!(transition("COMPLETED", "ACTIVE", true, false).is_err());
        assert!(transition("PENDING", "CANCELLED", false, true).is_ok());
        assert!(transition("ACTIVE", "COMPLETED", true, false).is_ok());
        assert!(transition("PENDING_OWNER_CONFIRMATION", "CONFIRMED", true, false).is_ok());
        assert!(transition("TEMP_HOLD", "CONFIRMED", true, false).is_err());
        assert!(transition("TEMP_HOLD", "CANCELLED", false, true).is_ok());
        assert!(transition("PAYMENT_PENDING", "REJECTED", true, false).is_ok());
        assert!(transition("RETURN_PENDING", "COMPLETED", true, false).is_ok());
    }
}
