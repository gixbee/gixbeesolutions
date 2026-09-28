/// Kept so callers can see the old assumed-hours conversion is not used.
/// Matching does not call this: a schedule is not stored, so mixed periods
/// stay neutral instead of becoming a made-up monthly amount.
#[allow(dead_code)]
pub fn to_monthly(amount: f32, period: &str) -> (f32, bool) {
    if !amount.is_finite() || amount < 0.0 {
        return (0.0, false);
    }
    match period.trim().to_ascii_uppercase().as_str() {
        "HOURLY" => (amount * 8.0 * 22.0, true),
        "DAILY" => (amount * 22.0, true),
        "WEEKLY" => (amount * 4.33, true),
        "PER_JOB" => (amount, false),
        _ => (amount, true),
    }
}

fn period_code(period: &str) -> Option<&'static str> {
    match period.trim().to_ascii_uppercase().as_str() {
        "HOURLY" => Some("HOURLY"),
        "DAILY" => Some("DAILY"),
        "WEEKLY" => Some("WEEKLY"),
        "MONTHLY" => Some("MONTHLY"),
        "PER_JOB" => Some("PER_JOB"),
        _ => None,
    }
}

/// 1.0 when the expectation sits inside the offer for the same pay period.
/// Different periods score neutral. A blank job period is monthly only when
/// the seeker is also monthly.
pub fn compatibility(job_min: f32, job_max: f32, job_period: &str, expected: f32, expected_period: &str) -> f32 {
    if expected <= 0.0 || (job_min <= 0.0 && job_max <= 0.0) {
        return 0.7;
    }
    let want = period_code(expected_period).unwrap_or("MONTHLY");
    let offer = match period_code(job_period) {
        Some(code) => code,
        None if want == "MONTHLY" => "MONTHLY",
        None => return 0.7,
    };
    if offer != want {
        return 0.7;
    }
    let low_raw = if job_min > 0.0 { job_min } else { job_max };
    let high_raw = if job_max > 0.0 { job_max } else { job_min };
    let low = low_raw.min(high_raw);
    let high = low_raw.max(high_raw);
    if expected >= low && expected <= high {
        return 1.0;
    }
    if expected < low {
        return 0.85;
    }
    let over = (expected - high) / high.max(1.0);
    if over <= 0.15 {
        0.6
    } else if over <= 0.4 {
        0.35
    } else {
        0.2
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn different_periods_are_neutral() {
        let score = compatibility(18_000.0, 24_000.0, "MONTHLY", 800.0, "DAILY");
        assert_eq!(score, 0.7, "{score}");
    }

    #[test]
    fn blank_job_period_against_hourly_is_neutral() {
        assert_eq!(compatibility(100.0, 150.0, "", 120.0, "HOURLY"), 0.7);
    }

    #[test]
    fn same_period_compares_the_amounts() {
        assert_eq!(
            compatibility(18_000.0, 24_000.0, "MONTHLY", 20_000.0, "MONTHLY"),
            1.0
        );
        assert_eq!(compatibility(80.0, 120.0, "HOURLY", 100.0, "HOURLY"), 1.0);
    }

    #[test]
    fn slightly_above_band_still_scores() {
        let score = compatibility(18_000.0, 24_000.0, "MONTHLY", 26_000.0, "MONTHLY");
        assert!(score > 0.0 && score < 1.0, "{score}");
    }
}
