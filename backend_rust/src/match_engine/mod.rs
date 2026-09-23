//! Board-first matching. Paid Smart Hiring fan-out stays in `crate::matching`.

pub mod embeddings;
pub mod events;
pub mod explanation;
pub mod features;
pub mod geo;
pub mod hard_filter;
pub mod persist;
pub mod reciprocal;
pub mod recommend;
pub mod salary;
pub mod semantic;
pub mod skills;
pub mod structured;
pub mod weights;

use async_trait::async_trait;

pub struct MatchContext {
    pub seeker_user_id: String,
}

pub struct MatchCandidate {
    pub id: String,
    pub features: features::FeatureSet,
}

pub struct RankedMatch {
    pub id: String,
    pub score: f32,
    pub candidate_fit: f32,
    pub employer_fit: f32,
    pub mutual_fit: f32,
    pub explanation: explanation::MatchExplanation,
}

#[async_trait]
pub trait CandidateRetriever {
    async fn retrieve(&self, ctx: &MatchContext) -> Result<Vec<MatchCandidate>, String>;
}

#[async_trait]
pub trait MatchRanker {
    async fn rank(
        &self,
        ctx: &MatchContext,
        candidates: Vec<MatchCandidate>,
    ) -> Result<Vec<RankedMatch>, String>;
}

pub trait SemanticMatcher {
    fn similarity(&self, left: &[f32], right: &[f32]) -> Option<f32>;
}

pub trait ReciprocalRanker {
    fn rank(&self, candidate_fit: f32, employer_fit: f32) -> reciprocal::ReciprocalScore;
}

pub trait EmbeddingProvider: Send + Sync {
    fn embed(&self, text: &str) -> Option<Vec<f32>>;
}

pub trait MatchExplanationBuilder {
    fn explain(&self, features: &features::FeatureSet) -> explanation::MatchExplanation;
}

pub struct StructuredRanker;

#[async_trait]
impl MatchRanker for StructuredRanker {
    async fn rank(
        &self,
        _ctx: &MatchContext,
        candidates: Vec<MatchCandidate>,
    ) -> Result<Vec<RankedMatch>, String> {
        let weights = weights::MatchingWeights::default();
        let mut out: Vec<RankedMatch> = candidates
            .into_iter()
            .map(|c| {
                let candidate_fit = structured::score(&c.features, &weights);
                let employer_fit = reciprocal::employer_fit(&c.features);
                let mutual = reciprocal::mutual(candidate_fit, employer_fit);
                let mut features = c.features.clone();
                features.candidate_fit = candidate_fit;
                features.employer_fit = employer_fit;
                RankedMatch {
                    id: c.id,
                    score: mutual.mutual_fit,
                    candidate_fit,
                    employer_fit,
                    mutual_fit: mutual.mutual_fit,
                    explanation: explanation::build(&features),
                }
            })
            .collect();
        out.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap_or(std::cmp::Ordering::Equal));
        Ok(out)
    }
}
