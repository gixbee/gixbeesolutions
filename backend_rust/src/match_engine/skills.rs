#[derive(Clone, Debug)]
pub struct SkillNeed {
    pub key: String,
    pub required: bool,
}

#[derive(Clone, Debug)]
pub struct SkillScore {
    pub matched: usize,
    pub total: usize,
    pub feature: f32,
    pub missing_required: Vec<String>,
}

pub fn normalize_skill(raw: &str) -> String {
    raw.trim().to_ascii_lowercase().split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Exact id/alias match counts fully. A related key counts as half.
/// Missing required skills lower the feature; they do not drop the pair.
pub fn score(needs: &[SkillNeed], have_keys: &[String], related: &[(String, String)]) -> SkillScore {
    if needs.is_empty() {
        return SkillScore {
            matched: 0,
            total: 0,
            feature: 0.7,
            missing_required: vec![],
        };
    }
    let have: std::collections::HashSet<&str> = have_keys.iter().map(|s| s.as_str()).collect();
    let mut matched = 0.0_f32;
    let mut exact = 0_usize;
    let mut missing_required = Vec::new();
    for need in needs {
        let key = normalize_skill(&need.key);
        if have.contains(key.as_str()) {
            matched += 1.0;
            exact += 1;
            continue;
        }
        let related_hit = related.iter().any(|(a, b)| {
            let a = normalize_skill(a);
            let b = normalize_skill(b);
            (a == key && have.contains(b.as_str())) || (b == key && have.contains(a.as_str()))
        });
        if related_hit {
            matched += 0.5;
        } else if need.required {
            missing_required.push(need.key.clone());
        }
    }
    let total = needs.len();
    SkillScore {
        matched: exact,
        total,
        feature: (matched / total as f32).clamp(0.0, 1.0),
        missing_required,
    }
}

pub fn parse_years(text: &str) -> f32 {
    let mut num = String::new();
    let mut seen_dot = false;
    for ch in text.chars() {
        if ch.is_ascii_digit() {
            num.push(ch);
        } else if ch == '.' && !seen_dot && !num.is_empty() {
            seen_dot = true;
            num.push(ch);
        } else if !num.is_empty() {
            break;
        }
    }
    num.parse().unwrap_or(0.0)
}

/// Gradual score. 1.5 years against a 2 year preference stays eligible.
pub fn experience_feature(candidate_years: f32, preferred_min: f32) -> (f32, bool) {
    if preferred_min <= 0.0 {
        return (1.0, false);
    }
    if candidate_years + 0.05 >= preferred_min {
        return (1.0, false);
    }
    let ratio = (candidate_years / preferred_min).clamp(0.15, 0.99);
    (ratio, true)
}

pub fn category_feature(job_category: &str, seeker_roles: &[String]) -> f32 {
    let job = normalize_skill(job_category);
    if job.is_empty() || seeker_roles.is_empty() {
        return 0.6;
    }
    for role in seeker_roles {
        let role = normalize_skill(role);
        if role == job {
            return 1.0;
        }
        if !role.is_empty() && (job.contains(&role) || role.contains(&job)) {
            return 0.75;
        }
    }
    0.25
}

pub fn employment_feature(job_type: &str, seeker_type: Option<&str>) -> f32 {
    let Some(seeker) = seeker_type.map(|s| s.trim()).filter(|s| !s.is_empty()) else {
        return 1.0;
    };
    let job_code = normalize_employment(job_type);
    let known = |code: &str| matches!(code, "ft" | "pt" | "intern" | "contract");
    let selected: Vec<String> = seeker
        .split(',')
        .map(|part| normalize_employment(part.trim()))
        .filter(|code| known(code))
        .collect();
    if selected.is_empty() || !known(&job_code) {
        return 1.0;
    }
    if selected.iter().any(|code| code == &job_code) {
        1.0
    } else {
        0.2
    }
}

pub fn normalize_employment(raw: &str) -> String {
    let s = raw.trim().to_ascii_lowercase();
    if s.contains("part") || s == "pt" {
        "pt".into()
    } else if s.contains("intern") {
        "intern".into()
    } else if s.contains("contract") {
        "contract".into()
    } else if s.contains("full") || s == "ft" {
        "ft".into()
    } else {
        s
    }
}

pub fn availability_feature(code: &str) -> f32 {
    match code.trim().to_ascii_uppercase().as_str() {
        "IMMEDIATE" | "" => 1.0,
        "DAYS_7" => 0.95,
        "DAYS_15" => 0.85,
        "DAYS_30" | "CUSTOM_DATE" => 0.7,
        "DAYS_60" => 0.6,
        _ => 0.55,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial_exact_match() {
        let needs = vec![
            SkillNeed { key: "Wiring".into(), required: true },
            SkillNeed { key: "MCB Installation".into(), required: true },
            SkillNeed { key: "Inverter".into(), required: true },
            SkillNeed { key: "Fault Finding".into(), required: true },
        ];
        let have = vec!["wiring".into(), "mcb installation".into(), "fault finding".into()];
        let score = score(&needs, &have, &[]);
        assert_eq!(score.matched, 3);
        assert_eq!(score.total, 4);
        assert!((score.feature - 0.75).abs() < 0.01);
    }

    #[test]
    fn related_skill_is_partial_credit() {
        let needs = vec![SkillNeed { key: "Electrical Installation".into(), required: true }];
        let have = vec!["wiring".into()];
        let score = score(&needs, &have, &[("electrical installation".into(), "wiring".into())]);
        assert_eq!(score.matched, 0);
        assert!((score.feature - 0.5).abs() < 0.01);
    }

    #[test]
    fn experience_gap_stays_positive() {
        let (feature, warn) = experience_feature(1.5, 2.0);
        assert!(warn);
        assert!(feature > 0.5 && feature < 1.0);
    }

    #[test]
    fn alias_normalises_spacing() {
        assert_eq!(normalize_skill("  Flutter   Dev "), "flutter dev");
    }
}
