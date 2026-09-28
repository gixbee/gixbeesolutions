use super::weights::MatchingWeights;

pub fn cosine(left: &[f32], right: &[f32]) -> Option<f32> {
    if left.is_empty() || left.len() != right.len() {
        return None;
    }
    let mut dot = 0.0_f32;
    let mut a = 0.0_f32;
    let mut b = 0.0_f32;
    for (x, y) in left.iter().zip(right) {
        dot += x * y;
        a += x * x;
        b += y * y;
    }
    let denom = a.sqrt() * b.sqrt();
    if denom <= f32::EPSILON {
        None
    } else {
        Some((dot / denom).clamp(-1.0, 1.0))
    }
}

/// Similarity in [-1, 1] mapped to 0–100, then blended. Weight 0 or a missing
/// vector leaves the structured score unchanged.
pub fn hybrid(structured: f32, similarity: Option<f32>, weights: &MatchingWeights) -> f32 {
    let Some(sim) = similarity else {
        return structured;
    };
    if weights.semantic <= 0.0 {
        return structured;
    }
    let semantic_score = ((sim + 1.0) / 2.0) * 100.0;
    let base = weights.structured_total();
    let total = base + weights.semantic;
    ((structured * base + semantic_score * weights.semantic) / total).clamp(0.0, 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_vectors_are_one() {
        let v = vec![1.0, 0.0, 1.0];
        assert!((cosine(&v, &v).unwrap() - 1.0).abs() < 0.001);
    }

    #[test]
    fn zero_semantic_weight_keeps_structured_score() {
        let mut weights = MatchingWeights::default();
        weights.semantic = 0.0;
        assert_eq!(hybrid(80.0, Some(0.2), &weights), 80.0);
    }
}
