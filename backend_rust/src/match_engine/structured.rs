use super::features::FeatureSet;
use super::weights::MatchingWeights;

pub fn score(features: &FeatureSet, weights: &MatchingWeights) -> f32 {
    let total = weights.structured_total();
    let raw = weights.skill * features.skill
        + weights.category * features.category
        + weights.distance * features.distance
        + weights.employment_type * features.employment_type
        + weights.salary * features.salary
        + weights.experience * features.experience
        + weights.availability * features.availability;
    (100.0 * raw / total).clamp(0.0, 100.0)
}
