#[derive(Clone, Debug)]
pub struct MatchingWeights {
    pub skill: f32,
    pub category: f32,
    pub distance: f32,
    pub employment_type: f32,
    pub salary: f32,
    pub experience: f32,
    pub availability: f32,
    pub semantic: f32,
}

impl Default for MatchingWeights {
    fn default() -> Self {
        Self {
            skill: 30.0,
            category: 25.0,
            distance: 15.0,
            employment_type: 10.0,
            salary: 10.0,
            experience: 5.0,
            availability: 5.0,
            semantic: 0.0,
        }
    }
}

impl MatchingWeights {
    pub fn from_row(
        skill: f32,
        category: f32,
        distance: f32,
        employment_type: f32,
        salary: f32,
        experience: f32,
        availability: f32,
        semantic: f32,
    ) -> Self {
        Self {
            skill,
            category,
            distance,
            employment_type,
            salary,
            experience,
            availability,
            semantic,
        }
    }

    /// Structured weights only. Semantic is applied later when a vector exists.
    pub fn structured_total(&self) -> f32 {
        (self.skill
            + self.category
            + self.distance
            + self.employment_type
            + self.salary
            + self.experience
            + self.availability)
            .max(1.0)
    }
}
