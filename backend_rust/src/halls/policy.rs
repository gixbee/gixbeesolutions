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
        let min = r
            .get("minDaysBeforeEvent")
            .and_then(|v| v.as_i64())
            .ok_or_else(|| {
                AppError::BadRequest(format!("{field}[{i}].minDaysBeforeEvent is required"))
            })? as i32;
        if min < 0 {
            return Err(AppError::BadRequest(format!(
                "{field}[{i}].minDaysBeforeEvent must be >= 0"
            )));
        }
        let max = match r.get("maxDaysBeforeEvent") {
            None | Some(Value::Null) => None,
            Some(v) => Some(v.as_i64().ok_or_else(|| {
                AppError::BadRequest(format!("{field}[{i}].maxDaysBeforeEvent must be an integer or null"))
            })? as i32),
        };
        if let Some(m) = max {
            if m < min {
                return Err(AppError::BadRequest(format!(
                    "{field}[{i}]: maxDaysBeforeEvent must be >= minDaysBeforeEvent"
                )));
            }
        }
        let pct = r
            .get("deductionPercent")
            .and_then(|v| v.as_i64())
            .ok_or_else(|| {
                AppError::BadRequest(format!("{field}[{i}].deductionPercent is required"))
            })? as i32;
        if !(0..=100).contains(&pct) {
            return Err(AppError::BadRequest(format!(
                "{field}[{i}].deductionPercent must be 0–100"
            )));
        }
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
        if next.min_days != max + 1 {
            return Err(AppError::BadRequest(format!(
                "{field}: gap or overlap between tiers ending at {max} and starting at {}",
                next.min_days
            )));
        }
    }
    Ok(tiers)
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
    fn accepts_complete_partition() {
        let rules = json!([
            {"minDaysBeforeEvent": 0, "maxDaysBeforeEvent": 2, "deductionPercent": 100},
            {"minDaysBeforeEvent": 3, "maxDaysBeforeEvent": 6, "deductionPercent": 75},
            {"minDaysBeforeEvent": 7, "maxDaysBeforeEvent": null, "deductionPercent": 10}
        ]);
        assert!(validate_policy_rules(&rules, "cancelRules").is_ok());
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
