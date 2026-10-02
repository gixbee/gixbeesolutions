use chrono::{DateTime, Months, Utc};
use serde_json::Value;

use crate::error::{AppError, AppResult};

/// Machine-readable cancel/reschedule tier.
#[derive(Debug, Clone)]
pub struct PolicyTier {
    pub min_days: i32,
    pub max_days: Option<i32>,
    pub deduction_percent: i32,
}

/// Validate cancelRules / rescheduleRules: complete partition of day counts ≥ 0,
/// no gaps/overlaps, percentages 0–100.
pub fn validate_policy_rules(rules: &Value, field: &str) -> AppResult<Vec<PolicyTier>> {
    let arr = rules.as_array().ok_or_else(|| {
        AppError::BadRequest(format!("{field} must be a non-empty array of tiers"))
    })?;
    if arr.is_empty() {
        return Err(AppError::BadRequest(format!(
            "{field} must include at least one tier"
        )));
    }
    let mut tiers = Vec::with_capacity(arr.len());
    for (i, r) in arr.iter().enumerate() {
        let min = policy_i32(
            r.get("minDaysBeforeEvent").and_then(|v| v.as_i64()),
            &format!("{field}[{i}].minDaysBeforeEvent"),
            0,
            i32::MAX as i64,
        )?;
        let max = match r.get("maxDaysBeforeEvent") {
            None | Some(Value::Null) => None,
            Some(v) => Some(policy_i32(
                v.as_i64(),
                &format!("{field}[{i}].maxDaysBeforeEvent"),
                0,
                i32::MAX as i64,
            )?),
        };
        if let Some(m) = max {
            if m < min {
                return Err(AppError::BadRequest(format!(
                    "{field}[{i}]: maxDaysBeforeEvent must be >= minDaysBeforeEvent"
                )));
            }
        }
        let pct = policy_i32(
            r.get("deductionPercent").and_then(|v| v.as_i64()),
            &format!("{field}[{i}].deductionPercent"),
            0,
            100,
        )?;
        tiers.push(PolicyTier {
            min_days: min,
            max_days: max,
            deduction_percent: pct,
        });
    }
    tiers.sort_by_key(|t| t.min_days);
    if tiers[0].min_days != 0 {
        return Err(AppError::BadRequest(format!(
            "{field}: first tier must start at minDaysBeforeEvent = 0"
        )));
    }
    let null_caps = tiers.iter().filter(|t| t.max_days.is_none()).count();
    if null_caps != 1 {
        return Err(AppError::BadRequest(format!(
            "{field}: exactly one tier must have maxDaysBeforeEvent = null (open upper bound)"
        )));
    }
    if tiers.last().unwrap().max_days.is_some() {
        return Err(AppError::BadRequest(format!(
            "{field}: the furthest tier must have maxDaysBeforeEvent = null"
        )));
    }
    for i in 0..tiers.len() - 1 {
        let cur = &tiers[i];
        let next = &tiers[i + 1];
        let Some(max) = cur.max_days else {
            return Err(AppError::BadRequest(format!(
                "{field}: only the last tier may omit maxDaysBeforeEvent"
            )));
        };
        let Some(expected) = max.checked_add(1) else {
            return Err(AppError::BadRequest(format!(
                "{field}: gap or overlap between tiers ending at {max} and starting at {}",
                next.min_days
            )));
        };
        if next.min_days != expected {
            return Err(AppError::BadRequest(format!(
                "{field}: gap or overlap between tiers ending at {max} and starting at {}",
                next.min_days
            )));
        }
    }
    Ok(tiers)
}

/// Reject values outside `min..=max` before converting. A truncating cast would
/// turn 4294967396 into 100 and let an oversized percentage pass.
fn policy_i32(value: Option<i64>, field: &str, min: i64, max: i64) -> AppResult<i32> {
    let n = value.ok_or_else(|| AppError::BadRequest(format!("{field} must be a whole number")))?;
    if !(min..=max).contains(&n) {
        return Err(AppError::BadRequest(format!(
            "{field} must be between {min} and {max}"
        )));
    }
    i32::try_from(n).map_err(|_| AppError::BadRequest(format!("{field} is out of range")))
}

/// Reject an interval the hall's saved book window or minimum notice does not allow.
/// Missing keys are not enforced, so older packages keep their previous behaviour
/// until the owner saves the new controls.
pub fn enforce_booking_window(
    pkg: &Value,
    start: DateTime<Utc>,
    now: DateTime<Utc>,
) -> AppResult<()> {
    if let Some(days) = pkg.get("minNoticeDays").and_then(|v| v.as_i64()) {
        if !(0..=365).contains(&days) {
            return Err(AppError::BadRequest("minNoticeDays is invalid".into()));
        }
        let earliest = now + chrono::Duration::days(days);
        if start < earliest {
            return Err(AppError::Conflict(format!(
                "This hall requires at least {days} days notice"
            )));
        }
    }
    if let Some(months) = pkg.get("bookWindowMonths").and_then(|v| v.as_i64()) {
        let Some(months_u) = u32::try_from(months).ok().filter(|m| (1..=36).contains(m)) else {
            return Err(AppError::BadRequest("bookWindowMonths is invalid".into()));
        };
        let latest = now
            .checked_add_months(Months::new(months_u))
            .ok_or_else(|| AppError::BadRequest("bookWindowMonths is too large".into()))?;
        if start > latest {
            return Err(AppError::Conflict(format!(
                "This hall only takes bookings up to {months} months ahead"
            )));
        }
    }
    Ok(())
}

pub fn validate_deduction_basis(v: Option<&Value>) -> AppResult<&'static str> {
    match v.and_then(|x| x.as_str()).unwrap_or("ADVANCE") {
        "ADVANCE" => Ok("ADVANCE"),
        "TOTAL_QUOTE" => Ok("TOTAL_QUOTE"),
        other => Err(AppError::BadRequest(format!(
            "deductionBasis must be ADVANCE or TOTAL_QUOTE (got {other})"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn booking_window_rejects_too_soon_and_too_far() {
        let now = Utc::now();
        let pkg = json!({"minNoticeDays": 3, "bookWindowMonths": 6});
        assert!(enforce_booking_window(&pkg, now + chrono::Duration::days(1), now).is_err());
        assert!(enforce_booking_window(&pkg, now + chrono::Duration::days(10), now).is_ok());
        assert!(enforce_booking_window(
            &pkg,
            now.checked_add_months(Months::new(7)).unwrap(),
            now
        )
        .is_err());
    }

    #[test]
    fn accepts_complete_partition() {
        let rules = json!([
            {"minDaysBeforeEvent": 0, "maxDaysBeforeEvent": 2, "deductionPercent": 100},
            {"minDaysBeforeEvent": 3, "maxDaysBeforeEvent": 6, "deductionPercent": 75},
            {"minDaysBeforeEvent": 7, "maxDaysBeforeEvent": null, "deductionPercent": 10}
        ]);
        assert!(validate_policy_rules(&rules, "cancelRules").is_ok());
    }

    #[test]
    fn rejects_percent_that_would_truncate_into_range() {
        let rules = json!([{
            "minDaysBeforeEvent": 0,
            "maxDaysBeforeEvent": null,
            "deductionPercent": 4294967396_i64
        }]);
        assert!(validate_policy_rules(&rules, "cancelRules").is_err());
    }

    #[test]
    fn rejects_day_count_that_would_truncate_to_zero() {
        let rules = json!([{
            "minDaysBeforeEvent": 4294967296_i64,
            "maxDaysBeforeEvent": null,
            "deductionPercent": 10
        }]);
        assert!(validate_policy_rules(&rules, "cancelRules").is_err());
    }

    #[test]
    fn rejects_gap() {
        let rules = json!([
            {"minDaysBeforeEvent": 0, "maxDaysBeforeEvent": 2, "deductionPercent": 100},
            {"minDaysBeforeEvent": 4, "maxDaysBeforeEvent": null, "deductionPercent": 10}
        ]);
        assert!(validate_policy_rules(&rules, "cancelRules").is_err());
    }
}
