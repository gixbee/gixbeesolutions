use serde_json::{json, Value};

/// Phone / email only after the candidate shares, or after they are hired.
pub fn contact_unlocked(progress: &Value, decision: &str) -> bool {
    decision == "HIRED"
        || progress
            .get("contactShared")
            .and_then(Value::as_bool)
            == Some(true)
}

/// Shared recruitment pipeline label for employer + seeker surfaces.
pub fn pipeline_label(response: &str, decision: &str, progress: &Value) -> String {
    let stage = progress
        .get("stage")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    if decision == "HIRED" || stage == "JOINED" {
        return "HIRED".into();
    }
    if stage == "WITHDRAWN" {
        return "WITHDRAWN".into();
    }
    if decision == "REJECTED" {
        return "NOT_SELECTED".into();
    }
    const LATE: [&str; 8] = [
        "INTERVIEW_PROPOSED",
        "INTERVIEW_ACCEPTED",
        "INTERVIEW_DECLINED",
        "INTERVIEW_COMPLETED",
        "OFFERED",
        "ACCEPTED",
        "OFFER_DECLINED",
        "SHORTLISTED",
    ];
    if LATE.contains(&stage.as_str()) {
        return stage;
    }
    if decision == "SHORTLISTED" {
        return "SHORTLISTED".into();
    }
    if response == "INTERESTED" {
        return "CHATTING".into();
    }
    if progress.get("invited").and_then(Value::as_bool) == Some(true) {
        return "INVITED".into();
    }
    if progress.get("viewedByEmployer").and_then(Value::as_bool) == Some(true)
        || progress.get("viewedByCandidate").and_then(Value::as_bool) == Some(true)
    {
        return "VIEWED".into();
    }
    "PENDING".into()
}

pub fn match_reasons(
    job_type_hit: bool,
    skill_overlap: &[String],
    location_hit: bool,
    salary_hit: bool,
    employment_hit: bool,
    experience_hit: bool,
) -> Vec<String> {
    let mut out = Vec::new();
    if job_type_hit {
        out.push("Job category".into());
    }
    if !skill_overlap.is_empty() {
        out.push(format!("Skills: {}", skill_overlap.join(", ")));
    }
    if employment_hit {
        out.push("Employment type".into());
    }
    if location_hit {
        out.push("Location".into());
    }
    if salary_hit {
        out.push("Salary".into());
    }
    if experience_hit {
        out.push("Experience".into());
    }
    out
}

pub fn skill_overlap(job: &[String], candidate: &[String]) -> Vec<String> {
    let wanted: Vec<String> = job
        .iter()
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    candidate
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| wanted.iter().any(|w| w == &s.to_lowercase()))
        .collect()
}

pub fn merge_progress(progress: &mut Value, patch: Value) {
    if let (Some(base), Some(extra)) = (progress.as_object_mut(), patch.as_object()) {
        for (k, v) in extra {
            base.insert(k.clone(), v.clone());
        }
    } else if progress.is_null() {
        *progress = patch;
    }
}

pub fn can_chat(response: &str, decision: &str) -> bool {
    response == "INTERESTED" && decision != "REJECTED"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contact_stays_locked_on_shortlist() {
        let p = json!({});
        assert!(!contact_unlocked(&p, "SHORTLISTED"));
        assert!(!contact_unlocked(&p, "PENDING"));
        assert!(contact_unlocked(&json!({"contactShared": true}), "SHORTLISTED"));
        assert!(contact_unlocked(&p, "HIRED"));
    }

    #[test]
    fn pipeline_moves_interested_to_chatting() {
        assert_eq!(pipeline_label("INTERESTED", "PENDING", &json!({})), "CHATTING");
        assert_eq!(
            pipeline_label("PENDING", "PENDING", &json!({"invited": true})),
            "INVITED"
        );
        assert_eq!(
            pipeline_label("PENDING", "PENDING", &json!({"viewedByEmployer": true})),
            "VIEWED"
        );
        assert_eq!(
            pipeline_label("INTERESTED", "SHORTLISTED", &json!({"stage": "OFFERED"})),
            "OFFERED"
        );
        assert_eq!(
            pipeline_label("INTERESTED", "REJECTED", &json!({})),
            "NOT_SELECTED"
        );
    }
}
