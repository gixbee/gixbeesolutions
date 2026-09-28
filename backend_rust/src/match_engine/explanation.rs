use super::features::FeatureSet;

#[derive(Clone, Debug)]
pub struct MatchExplanation {
    pub match_score: i32,
    pub reasons: Vec<String>,
    pub warnings: Vec<String>,
}

pub fn build(features: &FeatureSet) -> MatchExplanation {
    let mut reasons = Vec::new();
    let mut warnings = Vec::new();
    if features.skill_total > 0 && features.skill >= 0.5 {
        reasons.push(format!(
            "{} of {} required skills match",
            features.skill_matched, features.skill_total
        ));
    }
    if features.category >= 0.75 {
        reasons.push("Role matches what you are looking for".into());
    }
    if features.remote {
        reasons.push("Remote — distance does not affect this match".into());
    } else if features.distance_exact {
        if let Some(km) = features.distance_km {
            reasons.push(format!("{km:.1} km away"));
        }
    }
    if features.salary >= 0.85 {
        reasons.push("Salary matches your expectation".into());
    } else if features.salary < 0.5 && features.salary > 0.0 {
        warnings.push("Salary is outside the posted range".into());
    }
    if features.availability >= 0.99 {
        reasons.push("Available immediately".into());
    }
    if features.experience_warning {
        warnings.push(format!(
            "Employer prefers {} years experience; you have {} years",
            trim_years(features.preferred_years),
            trim_years(features.candidate_years)
        ));
    }
    let shown = features.candidate_fit.max(features.employer_fit);
    let score = if features.candidate_fit > 0.0 && features.employer_fit > 0.0 {
        (features.candidate_fit * features.employer_fit).sqrt()
    } else {
        shown
    };
    MatchExplanation {
        match_score: score.round().clamp(0.0, 100.0) as i32,
        reasons,
        warnings,
    }
}

fn trim_years(years: f32) -> String {
    if (years - years.round()).abs() < 0.05 {
        format!("{}", years.round() as i32)
    } else {
        format!("{years:.1}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reasons_come_from_features_only() {
        let features = FeatureSet {
            category: 1.0,
            skill: 0.8,
            skill_matched: 5,
            skill_total: 6,
            distance: 0.9,
            distance_km: Some(3.2),
            distance_exact: true,
            employment_type: 1.0,
            salary: 1.0,
            experience: 0.75,
            experience_warning: true,
            candidate_years: 1.5,
            preferred_years: 2.0,
            availability: 1.0,
            availability_label: "IMMEDIATE".into(),
            remote: false,
            candidate_fit: 90.0,
            employer_fit: 80.0,
        };
        let explained = build(&features);
        assert!(explained.reasons.iter().any(|r| r.contains("5 of 6")));
        assert!(explained.reasons.iter().any(|r| r.contains("3.2 km")));
        assert!(explained.reasons.iter().any(|r| r.contains("Salary matches")));
        assert!(explained.reasons.iter().any(|r| r.contains("Available immediately")));
        assert!(explained.warnings.iter().any(|w| w.contains("1.5")));
        assert!(explained.match_score > 0);
    }

    #[test]
    fn missing_pin_does_not_invent_kilometres() {
        let features = FeatureSet {
            category: 0.2,
            skill: 0.2,
            skill_matched: 0,
            skill_total: 2,
            distance: 0.7,
            distance_km: None,
            distance_exact: false,
            employment_type: 1.0,
            salary: 0.4,
            experience: 1.0,
            experience_warning: false,
            candidate_years: 0.0,
            preferred_years: 0.0,
            availability: 0.5,
            availability_label: "DAYS_90".into(),
            remote: false,
            candidate_fit: 40.0,
            employer_fit: 40.0,
        };
        let explained = build(&features);
        assert!(explained.reasons.iter().all(|r| !r.contains("km")));
    }
}
