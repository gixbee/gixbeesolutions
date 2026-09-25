use sqlx::{PgPool, Row, Transaction};

use crate::error::AppResult;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Domain {
    HiringMaster,
    LocationMaster,
    ServiceMaster,
    PublicListings,
}

impl Domain {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::HiringMaster => "hiring_master",
            Self::LocationMaster => "location_master",
            Self::ServiceMaster => "service_master",
            Self::PublicListings => "public_listings",
        }
    }
}

pub async fn ensure_table(db: &PgPool) -> AppResult<()> {
    sqlx::query(
        r#"CREATE TABLE IF NOT EXISTS cache_versions (
            domain TEXT PRIMARY KEY,
            version BIGINT NOT NULL DEFAULT 1,
            "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"#,
    )
    .execute(db)
    .await?;
    for domain in [
        Domain::HiringMaster,
        Domain::LocationMaster,
        Domain::ServiceMaster,
        Domain::PublicListings,
    ] {
        sqlx::query(
            r#"INSERT INTO cache_versions (domain, version) VALUES ($1, 1)
               ON CONFLICT (domain) DO NOTHING"#,
        )
        .bind(domain.as_str())
        .execute(db)
        .await?;
    }
    Ok(())
}

pub async fn current_version(db: &PgPool, domain: Domain) -> AppResult<i64> {
    let row = sqlx::query(r#"SELECT version FROM cache_versions WHERE domain = $1"#)
        .bind(domain.as_str())
        .fetch_optional(db)
        .await?;
    Ok(row
        .map(|r| r.get::<i64, _>("version"))
        .unwrap_or(1))
}

pub async fn bump_now(db: &PgPool, domain: Domain) -> AppResult<i64> {
    let row = sqlx::query(
        r#"UPDATE cache_versions SET version = version + 1, "updatedAt" = NOW()
           WHERE domain = $1 RETURNING version"#,
    )
    .bind(domain.as_str())
    .fetch_optional(db)
    .await?;
    if let Some(r) = row {
        tracing::info!(target: "cache", domain = domain.as_str(), version = r.get::<i64, _>("version"), "version bumped");
        return Ok(r.get("version"));
    }
    sqlx::query(
        r#"INSERT INTO cache_versions (domain, version) VALUES ($1, 2)
           ON CONFLICT (domain) DO UPDATE SET version = cache_versions.version + 1, "updatedAt" = NOW()"#,
    )
    .bind(domain.as_str())
    .execute(db)
    .await?;
    current_version(db, domain).await
}

/// Bump cache version and commit the surrounding mutation transaction atomically.
pub async fn commit_bump_tx(
    mut tx: Transaction<'_, sqlx::Postgres>,
    domain: Domain,
) -> AppResult<()> {
    bump_in_tx(&mut tx, domain).await?;
    tx.commit().await?;
    Ok(())
}

pub async fn bump_in_tx(
    tx: &mut Transaction<'_, sqlx::Postgres>,
    domain: Domain,
) -> AppResult<i64> {
    let row = sqlx::query(
        r#"UPDATE cache_versions SET version = version + 1, "updatedAt" = NOW()
           WHERE domain = $1 RETURNING version"#,
    )
    .bind(domain.as_str())
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(r) = row {
        return Ok(r.get("version"));
    }
    sqlx::query(
        r#"INSERT INTO cache_versions (domain, version) VALUES ($1, 2)
           ON CONFLICT (domain) DO UPDATE SET version = cache_versions.version + 1, "updatedAt" = NOW()"#,
    )
    .bind(domain.as_str())
    .execute(&mut **tx)
    .await?;
    let row = sqlx::query(r#"SELECT version FROM cache_versions WHERE domain = $1"#)
        .bind(domain.as_str())
        .fetch_one(&mut **tx)
        .await?;
    Ok(row.get("version"))
}

pub async fn all_versions(db: &PgPool) -> AppResult<serde_json::Value> {
    let rows = sqlx::query(r#"SELECT domain, version, "updatedAt" FROM cache_versions ORDER BY domain"#)
        .fetch_all(db)
        .await?;
    Ok(serde_json::json!({
        "versions": rows.iter().map(|r| serde_json::json!({
            "domain": r.get::<String,_>("domain"),
            "version": r.get::<i64,_>("version"),
            "updatedAt": r.get::<chrono::DateTime<chrono::Utc>,_>("updatedAt"),
        })).collect::<Vec<_>>()
    }))
}
