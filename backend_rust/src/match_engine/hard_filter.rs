#[derive(Clone, Debug)]
pub struct GateInput {
    pub job_published: bool,
    pub business_verified: bool,
    pub profile_active: bool,
    pub work_mode: String,
    pub seeker_work_mode: Option<String>,
    pub job_employment: String,
    pub seeker_employment: Option<String>,
    pub distance_km: Option<f64>,
    pub travel_radius_km: f64,
    pub job_position_id: Option<String>,
    pub seeker_position_ids: Option<String>,
}

pub fn admit(gate: &GateInput) -> Result<(), &'static str> {
    if !gate.job_published {
        return Err("inactive job");
    }
    if !gate.business_verified {
        return Err("unverified business");
    }
    if !gate.profile_active {
        return Err("inactive candidate");
    }
    let job_mode = gate.work_mode.trim().to_ascii_uppercase();
    if let Some(pref) = gate.seeker_work_mode.as_deref().map(|s| s.trim().to_ascii_uppercase()) {
        if pref == "REMOTE" && job_mode == "ONSITE" {
            return Err("work mode");
        }
    }
    if let Some(seeker_type) = gate
        .seeker_employment
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let job_code = super::skills::normalize_employment(&gate.job_employment);
        let known = |code: &str| matches!(code, "ft" | "pt" | "intern" | "contract");
        let selected: Vec<String> = seeker_type
            .split(',')
            .map(|part| super::skills::normalize_employment(part.trim()))
            .filter(|code| known(code))
            .collect();
        if known(&job_code) && !selected.is_empty() && !selected.iter().any(|code| code == &job_code) {
            return Err("employment type");
        }
    }
    if let (Some(job_position), Some(seeker_positions)) = (
        gate.job_position_id.as_deref().map(str::trim).filter(|s| !s.is_empty()),
        gate.seeker_position_ids.as_deref().map(str::trim).filter(|s| !s.is_empty()),
    ) {
        let matches = seeker_positions.split(',').any(|id| id.trim() == job_position);
        if !matches {
            return Err("position");
        }
    }
    if job_mode != "REMOTE" {
        if let Some(km) = gate.distance_km {
            if km > gate.travel_radius_km {
                return Err("outside radius");
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn open() -> GateInput {
        GateInput {
            job_published: true,
            business_verified: true,
            profile_active: true,
            work_mode: "ONSITE".into(),
            seeker_work_mode: None,
            job_employment: "Full Time".into(),
            seeker_employment: None,
            distance_km: Some(4.0),
            travel_radius_km: 25.0,
            job_position_id: None,
            seeker_position_ids: None,
        }
    }

    #[test]
    fn inactive_job_and_unverified_business_are_rejected() {
        let mut gate = open();
        gate.job_published = false;
        assert_eq!(admit(&gate), Err("inactive job"));
        gate = open();
        gate.business_verified = false;
        assert_eq!(admit(&gate), Err("unverified business"));
        gate = open();
        gate.profile_active = false;
        assert_eq!(admit(&gate), Err("inactive candidate"));
    }

    #[test]
    fn employment_mismatch_is_rejected_when_both_sides_set_it() {
        let mut gate = open();
        gate.seeker_employment = Some("Part Time".into());
        assert_eq!(admit(&gate), Err("employment type"));
    }

    #[test]
    fn any_selected_employment_type_is_admitted() {
        let mut gate = open();
        gate.job_employment = "Contract".into();
        gate.seeker_employment = Some("FT,CONTRACT".into());
        assert!(admit(&gate).is_ok());
        gate.seeker_employment = Some("GIG".into());
        assert!(admit(&gate).is_ok());
    }

    #[test]
    fn onsite_outside_radius_is_rejected_remote_is_not() {
        let mut gate = open();
        gate.distance_km = Some(30.0);
        gate.travel_radius_km = 10.0;
        assert_eq!(admit(&gate), Err("outside radius"));
        gate.work_mode = "REMOTE".into();
        gate.distance_km = Some(500.0);
        assert!(admit(&gate).is_ok());
    }
}
