use super::EmbeddingProvider;

/// No network call. Recommendations keep working when no model is configured.
pub struct DisabledEmbeddings;

impl EmbeddingProvider for DisabledEmbeddings {
    fn embed(&self, _text: &str) -> Option<Vec<f32>> {
        None
    }
}

pub fn provider() -> DisabledEmbeddings {
    DisabledEmbeddings
}

pub const MODEL: &str = "local-hash-64";

pub fn embed_text(text: &str) -> Option<Vec<f32>> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(hash_embed(trimmed))
}

pub fn to_literal(values: &[f32]) -> String {
    let body = values
        .iter()
        .map(|value| format!("{value:.6}"))
        .collect::<Vec<_>>()
        .join(",");
    format!("[{body}]")
}

pub fn job_text(title: &str, category: &str, description: &str, skills: &[String]) -> String {
    format!(
        "{title}\n{category}\n{}\n{description}",
        skills.join(", ")
    )
}

pub fn candidate_text(roles: &[String], skills: &[String], summary: &str) -> String {
    format!("{}\n{}\n{summary}", roles.join(", "), skills.join(", "))
}

/// Deterministic stand-in used by tests and by a future local model of dim 64.
/// Not used for live ranking while semantic_weight is 0.
pub fn hash_embed(text: &str) -> Vec<f32> {
    let mut out = vec![0.0_f32; 64];
    for (i, byte) in text.bytes().enumerate() {
        out[i % 64] += (byte as f32) / 255.0;
    }
    let norm = out.iter().map(|v| v * v).sum::<f32>().sqrt();
    if norm > 0.0 {
        for v in &mut out {
            *v /= norm;
        }
    }
    out
}
