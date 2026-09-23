/// Normalize any supported pay period into an approximate monthly rupee amount.
/// `PER_JOB` is left as a one-off and flagged so it is not treated as monthly.
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

/// 1.0 when the expectation sits inside the offer. Above the band lowers the
/// score but does not reject the pair.
pub fn compatibility(job_min: f32, job_max: f32, job_period: &str, expected: f32, expected_period: &str) -> f32 {
    if expected <= 0.0 || (job_min <= 0.0 && job_max <= 0.0) {
        return 0.7;
    }
    let (offer_min, offer_monthly) = to_monthly(if job_min > 0.0 { job_min } else { job_max }, job_period);
    let (offer_max, _) = to_monthly(if job_max > 0.0 { job_max } else { job_min }, job_period);
    let (want, want_monthly) = to_monthly(expected, expected_period);
    if offer_monthly != want_monthly {
        return 0.45;
    }
    let low = offer_min.min(offer_max);
    let high = offer_min.max(offer_max);
    if want >= low && want <= high {
        return 1.0;
    }
    if want < low {
        return 0.85;
    }
    let over = (want - high) / high.max(1.0);
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
    fn daily_normalises_before_compare() {
        let score = compatibility(18_000.0, 24_000.0, "MONTHLY", 800.0, "DAILY");
        assert!(score >= 0.85, "{score}");
    }

    #[test]
    fn inside_band_is_excellent() {
        assert_eq!(
            compatibility(18_000.0, 24_000.0, "MONTHLY", 20_000.0, "MONTHLY"),
            1.0
        );
    }

    #[test]
    fn slightly_above_band_still_scores() {
        let score = compatibility(18_000.0, 24_000.0, "MONTHLY", 26_000.0, "MONTHLY");
        assert!(score > 0.0 && score < 1.0, "{score}");
    }
}
