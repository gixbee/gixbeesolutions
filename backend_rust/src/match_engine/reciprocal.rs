use super::features::FeatureSet;

#[derive(Clone, Copy, Debug)]
pub struct ReciprocalScore {
    pub candidate_fit: f32,
    pub employer_fit: f32,
    pub mutual_fit: f32,
}

pub fn employer_fit(features: &FeatureSet) -> f32 {
    let raw = 0.45 * features.skill
        + 0.25 * features.experience
        + 0.20 * features.salary
        + 0.10 * features.availability;
    (raw * 100.0).clamp(0.0, 100.0)
}

pub fn mutual(candidate_fit: f32, employer_fit: f32) -> ReciprocalScore {
    let c = candidate_fit.clamp(0.0, 100.0);
    let e = employer_fit.clamp(0.0, 100.0);
    ReciprocalScore {
        candidate_fit: c,
        employer_fit: e,
        mutual_fit: (c * e).sqrt(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::match_engine::features::FeatureSet;

    fn blank() -> FeatureSet {
        FeatureSet {
            category: 1.0,
            skill: 1.0,
            skill_matched: 1,
            skill_total: 1,
            distance: 1.0,
            distance_km: Some(1.0),
            distance_exact: true,
            employment_type: 1.0,
            salary: 1.0,
            experience: 1.0,
            experience_warning: false,
            candidate_years: 2.0,
            preferred_years: 2.0,
            availability: 1.0,
            availability_label: "IMMEDIATE".into(),
            remote: false,
            candidate_fit: 0.0,
            employer_fit: 0.0,
        }
    }

    #[test]
    fn mutual_is_geometric_mean() {
        let score = mutual(64.0, 100.0);
        assert!((score.mutual_fit - 80.0).abs() < 0.01);
    }

    #[test]
    fn employer_fit_uses_skill_weight() {
        let mut features = blank();
        features.skill = 0.0;
        assert!(employer_fit(&features) < 60.0);
    }
}
