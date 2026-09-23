use super::skills::{self, SkillNeed};

#[derive(Clone, Debug)]
pub struct FeatureSet {
    pub category: f32,
    pub skill: f32,
    pub skill_matched: usize,
    pub skill_total: usize,
    pub distance: f32,
    pub distance_km: Option<f64>,
    pub distance_exact: bool,
    pub employment_type: f32,
    pub salary: f32,
    pub experience: f32,
    pub experience_warning: bool,
    pub candidate_years: f32,
    pub preferred_years: f32,
    pub availability: f32,
    pub availability_label: String,
    pub remote: bool,
    pub candidate_fit: f32,
    pub employer_fit: f32,
}

#[derive(Clone, Debug)]
pub struct PairInput {
    pub job_category: String,
    pub seeker_roles: Vec<String>,
    pub job_skills: Vec<SkillNeed>,
    pub seeker_skills: Vec<String>,
    pub related: Vec<(String, String)>,
    pub distance_km: Option<f64>,
    pub distance_exact: bool,
    pub travel_radius_km: f64,
    pub remote: bool,
    pub job_employment: String,
    pub seeker_employment: Option<String>,
    pub job_salary_min: f32,
    pub job_salary_max: f32,
    pub job_salary_period: String,
    pub expected_salary: f32,
    pub expected_period: String,
    pub candidate_years: f32,
    pub preferred_years: f32,
    pub availability: String,
}

pub fn build(input: &PairInput) -> Option<FeatureSet> {
    let distance = match super::geo::distance_feature(
        input.distance_km.unwrap_or(0.0),
        input.travel_radius_km,
        input.remote || input.distance_km.is_none(),
    ) {
        Some(v) => v,
        None => return None,
    };
    let distance = if input.distance_km.is_none() && !input.remote {
        0.7
    } else {
        distance
    };
    let skills = skills::score(&input.job_skills, &input.seeker_skills, &input.related);
    let (experience, experience_warning) =
        skills::experience_feature(input.candidate_years, input.preferred_years);
    Some(FeatureSet {
        category: skills::category_feature(&input.job_category, &input.seeker_roles),
        skill: skills.feature,
        skill_matched: skills.matched,
        skill_total: skills.total,
        distance,
        distance_km: input.distance_km,
        distance_exact: input.distance_exact,
        employment_type: skills::employment_feature(&input.job_employment, input.seeker_employment.as_deref()),
        salary: super::salary::compatibility(
            input.job_salary_min,
            input.job_salary_max,
            &input.job_salary_period,
            input.expected_salary,
            &input.expected_period,
        ),
        experience,
        experience_warning,
        candidate_years: input.candidate_years,
        preferred_years: input.preferred_years,
        availability: skills::availability_feature(&input.availability),
        availability_label: input.availability.clone(),
        remote: input.remote,
        candidate_fit: 0.0,
        employer_fit: 0.0,
    })
}
