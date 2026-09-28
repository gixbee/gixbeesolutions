use uuid::Uuid;

use crate::state::AppState;

use super::embeddings::{self, MODEL};
use super::skills::normalize_skill;

pub async fn save_job_embedding(state: &AppState, job_id: Uuid, text: &str) {
    let Some(vector) = embeddings::embed_text(text) else { return };
    let _ = sqlx::query(
        r#"INSERT INTO job_embeddings ("jobPostId", embedding, model)
           VALUES ($1, $2::vector, $3)
           ON CONFLICT ("jobPostId") DO UPDATE
           SET embedding = EXCLUDED.embedding, model = EXCLUDED.model, "updatedAt" = now()"#,
    )
    .bind(job_id)
    .bind(embeddings::to_literal(&vector))
    .bind(MODEL)
    .execute(&state.db)
    .await;
}

pub async fn save_candidate_embedding(state: &AppState, profile_id: Uuid, text: &str) {
    let Some(vector) = embeddings::embed_text(text) else { return };
    let _ = sqlx::query(
        r#"INSERT INTO candidate_embeddings ("talentProfileId", embedding, model)
           VALUES ($1, $2::vector, $3)
           ON CONFLICT ("talentProfileId") DO UPDATE
           SET embedding = EXCLUDED.embedding, model = EXCLUDED.model, "updatedAt" = now()"#,
    )
    .bind(profile_id)
    .bind(embeddings::to_literal(&vector))
    .bind(MODEL)
    .execute(&state.db)
    .await;
}

pub async fn backfill_embeddings(state: &AppState) {
    let _ = state.redis.del("matching:config").await;
    let jobs = sqlx::query(
        r#"SELECT j.id, j.title, COALESCE(j."jobType", '') AS category, j.description, j."requiredSkills"
           FROM job_posts j
           WHERE NOT EXISTS (SELECT 1 FROM job_embeddings e WHERE e."jobPostId" = j.id)
           LIMIT 500"#,
    )
    .fetch_all(&state.db)
    .await;
    if let Ok(jobs) = jobs {
        for row in jobs {
            use sqlx::Row;
            let id: Uuid = row.get("id");
            let skills = crate::common::pg::string_list(&row, "requiredSkills");
            let text = embeddings::job_text(
                &row.get::<String, _>("title"),
                &row.get::<String, _>("category"),
                &row.get::<String, _>("description"),
                &skills,
            );
            save_job_embedding(state, id, &text).await;
        }
    }
    let people = sqlx::query(
        r#"SELECT id, skills, "preferredRoles", COALESCE(experience, '') AS experience
           FROM talent_profiles
           WHERE NOT EXISTS (
             SELECT 1 FROM candidate_embeddings e WHERE e."talentProfileId" = talent_profiles.id
           )
           LIMIT 500"#,
    )
    .fetch_all(&state.db)
    .await;
    if let Ok(people) = people {
        for row in people {
            use sqlx::Row;
            let id: Uuid = row.get("id");
            let skills = crate::common::pg::string_list(&row, "skills");
            let roles = crate::common::pg::string_list(&row, "preferredRoles");
            let text = embeddings::candidate_text(&roles, &skills, &row.get::<String, _>("experience"));
            save_candidate_embedding(state, id, &text).await;
        }
    }
}

/// Best-effort link from free-text skill labels onto canonical skill ids.
pub async fn sync_job_skills(state: &AppState, job_id: Uuid, labels: &[String]) {
    for label in labels {
        let key = normalize_skill(label);
        if key.is_empty() {
            continue;
        }
        let skill_id = ensure_skill(state, label, &key).await;
        let Ok(skill_id) = skill_id else { continue };
        let _ = sqlx::query(
            r#"INSERT INTO job_post_skills ("jobPostId", "skillId", "isRequired", importance)
               VALUES ($1,$2,true,1) ON CONFLICT DO NOTHING"#,
        )
        .bind(job_id)
        .bind(skill_id)
        .execute(&state.db)
        .await;
    }
}

pub async fn sync_candidate_skills(state: &AppState, profile_id: Uuid, labels: &[String]) {
    for label in labels {
        let key = normalize_skill(label);
        if key.is_empty() {
            continue;
        }
        let Ok(skill_id) = ensure_skill(state, label, &key).await else { continue };
        let _ = sqlx::query(
            r#"INSERT INTO candidate_skills ("talentProfileId", "skillId")
               VALUES ($1,$2) ON CONFLICT DO NOTHING"#,
        )
        .bind(profile_id)
        .bind(skill_id)
        .execute(&state.db)
        .await;
    }
}

async fn ensure_skill(state: &AppState, label: &str, key: &str) -> Result<Uuid, ()> {
    if let Ok(Some(id)) = sqlx::query_scalar::<_, Uuid>(
        r#"SELECT id FROM skills WHERE "normalizedName" = $1
           UNION SELECT "skillId" FROM skill_aliases WHERE "normalizedAlias" = $1
           LIMIT 1"#,
    )
    .bind(key)
    .fetch_optional(&state.db)
    .await
    {
        return Ok(id);
    }
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO skills (id, name, "normalizedName") VALUES ($1,$2,$3) ON CONFLICT ("normalizedName") DO NOTHING"#)
        .bind(id)
        .bind(label.trim())
        .bind(key)
        .execute(&state.db)
        .await
        .map_err(|_| ())?;
    sqlx::query_scalar::<_, Uuid>(r#"SELECT id FROM skills WHERE "normalizedName"=$1"#)
        .bind(key)
        .fetch_one(&state.db)
        .await
        .map_err(|_| ())
}
