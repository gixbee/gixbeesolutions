use axum::{
    extract::{Path, Query, State},
    http::HeaderMap,
    response::Response,
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

const BUNDLED: &str = include_str!("../../data/hiring-catalogue.json");
const LEGACY_MAP: &str = include_str!("../../data/hiring-catalogue-legacy-map.json");

fn bundled_version() -> String {
    serde_json::from_str::<Value>(BUNDLED)
        .ok()
        .and_then(|v| v.get("version").and_then(|s| s.as_str()).map(String::from))
        .unwrap_or_else(|| "unknown".into())
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(snapshot))
        .route("/positions", get(search_positions))
        .route("/positions/{id}", get(position_detail))
        .route("/admin/import", post(import_bundled))
        .route("/admin/sectors", post(create_sector))
        .route("/admin/sectors/{id}", patch(patch_sector))
        .route("/admin/positions", post(create_position))
        .route("/admin/positions/{id}", patch(patch_position))
        .route("/admin/specializations", post(create_specialization))
        .route("/admin/specializations/{id}", patch(patch_active_specialization))
        .route("/admin/skills", post(create_skill))
        .route("/admin/skills/{id}", patch(patch_skill))
        .route("/admin/position-skills", post(link_skill))
        .route("/admin/qualifications", post(create_qualification))
        .route("/admin/qualifications/{id}", patch(patch_qualification))
        .route("/admin/employment-types/{code}", patch(patch_employment))
        .route("/admin/aliases", post(create_alias))
        .route("/admin/aliases/{id}", patch(patch_alias))
        .route("/admin/languages", post(create_language))
        .route("/admin/languages/{id}", patch(patch_language))
        .route("/admin/legacy-map", get(admin_legacy_map))
}

async fn admin_legacy_map(user: AuthUser) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let map: Value = serde_json::from_str(LEGACY_MAP).unwrap_or(json!({}));
    Ok(Json(map))
}

pub fn location_routes() -> Router<AppState> {
    Router::new()
        .route("/search", get(search_locations))
        .route("/admin/list", get(admin_list_locations))
        .route("/{id}", get(location_detail))
        .route("/admin", post(create_location))
        .route("/admin/{id}", patch(patch_location))
        .route("/admin/{id}/aliases", post(create_location_alias))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PageQuery {
    #[serde(default)]
    sector_id: Option<String>,
    #[serde(rename = "q", default)]
    q: Option<String>,
    #[serde(default)]
    limit: Option<i64>,
    #[serde(default)]
    offset: Option<i64>,
    #[serde(default)]
    include_inactive: Option<bool>,
}

async fn snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<PageQuery>,
) -> AppResult<Response> {
    let include_inactive = q.include_inactive.unwrap_or(false);
    let suffix = if include_inactive {
        "snapshot:inactive"
    } else {
        "snapshot:active"
    };
    let if_none = headers
        .get(axum::http::header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let ttl = state.cache.hiring_master_ttl_secs;
    let db_state = state.clone();
    let cached = crate::cache::read_through(
        &state,
        crate::cache::versions::Domain::HiringMaster,
        suffix,
        ttl,
        None,
        if_none,
        || {
            let state = db_state.clone();
            Box::pin(async move {
                load_hiring_snapshot(&state, include_inactive).await
            })
        },
    )
    .await?;
    if cached.json.is_null() {
        return Ok(crate::cache::http::not_modified(&cached.etag));
    }
    Ok(crate::cache::http::json_cached(
        cached.json,
        &cached.etag,
        cached.outcome,
    ))
}

async fn load_hiring_snapshot(state: &AppState, include_inactive: bool) -> AppResult<Value> {
    let cache_version =
        crate::cache::versions::current_version(&state.db, crate::cache::versions::Domain::HiringMaster)
            .await?;
    let sectors = sqlx::query(
        r#"SELECT id, label, subtitle, icon, color, "sortOrder", "isActive" FROM hiring_sectors WHERE ($1::bool OR "isActive") ORDER BY "sortOrder", label"#,
    )
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await?;
    let employment = sqlx::query(
        r#"SELECT code, label, "isActive" FROM hiring_employment_types WHERE ($1::bool OR "isActive") ORDER BY "sortOrder", code"#,
    )
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await?;
    let periods = sqlx::query(
        r#"SELECT code, label, "isActive" FROM hiring_salary_periods WHERE ($1::bool OR "isActive") ORDER BY "sortOrder", code"#,
    )
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await?;
    let qualifications = sqlx::query(
        r#"SELECT id, label, rank, professional, "isActive" FROM hiring_qualifications WHERE ($1::bool OR "isActive") ORDER BY "sortOrder", label"#,
    )
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await?;
    let languages = sqlx::query(
        r#"SELECT id, label, "quickPick", "sortOrder", "isActive" FROM hiring_languages WHERE ($1::bool OR "isActive") ORDER BY "sortOrder", label"#,
    )
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();
    Ok(json!({
        "bundledVersion": bundled_version(),
        "cacheVersion": cache_version,
        "sectors": sectors.iter().map(|r| json!({
            "id": r.get::<String,_>("id"),
            "label": r.get::<String,_>("label"),
            "subtitle": r.get::<String,_>("subtitle"),
            "icon": r.get::<String,_>("icon"),
            "color": r.get::<String,_>("color"),
            "isActive": r.get::<bool,_>("isActive"),
        })).collect::<Vec<_>>(),
        "employmentTypes": employment.iter().map(|r| json!({
            "code": r.get::<String,_>("code"),
            "label": r.get::<String,_>("label"),
            "isActive": r.get::<bool,_>("isActive"),
        })).collect::<Vec<_>>(),
        "salaryPeriods": periods.iter().map(|r| json!({
            "code": r.get::<String,_>("code"),
            "label": r.get::<String,_>("label"),
            "isActive": r.get::<bool,_>("isActive"),
        })).collect::<Vec<_>>(),
        "qualifications": qualifications.iter().map(|r| json!({
            "id": r.get::<String,_>("id"),
            "label": r.get::<String,_>("label"),
            "rank": r.get::<Option<i32>,_>("rank"),
            "professional": r.get::<bool,_>("professional"),
            "isActive": r.get::<bool,_>("isActive"),
        })).collect::<Vec<_>>(),
        "languages": languages.iter().map(|r| json!({
            "id": r.get::<String,_>("id"),
            "label": r.get::<String,_>("label"),
            "quickPick": r.get::<bool,_>("quickPick"),
            "isActive": r.get::<bool,_>("isActive"),
        })).collect::<Vec<_>>(),
    }))
}

async fn search_positions(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<PageQuery>,
) -> AppResult<Response> {
    let limit = q.limit.unwrap_or(30).clamp(1, 100);
    let offset = q.offset.unwrap_or(0).max(0);
    let term = q.q.unwrap_or_default().trim().to_string();
    if term.chars().count() > 80 {
        return Err(AppError::BadRequest("Search query is too long".into()));
    }
    let sector = q.sector_id.unwrap_or_default();
    let include_inactive = q.include_inactive.unwrap_or(false);
    let suffix = format!(
        "pos:{sector}:{include_inactive}:{}:{limit}:{offset}",
        crate::cache::normalize_search_query(&term)
    );
    let if_none = headers
        .get(axum::http::header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let db_state = state.clone();
    let sector_key = sector.clone();
    let term_key = term.clone();
    let cached = crate::cache::read_through(
        &state,
        crate::cache::versions::Domain::HiringMaster,
        &suffix,
        state.cache.hiring_master_ttl_secs,
        None,
        if_none,
        || {
            let state = db_state.clone();
            let sector = sector_key.clone();
            let term = term_key.clone();
            Box::pin(async move {
                load_position_search(&state, &sector, &term, limit, offset, include_inactive).await
            })
        },
    )
    .await?;
    if cached.json.is_null() {
        return Ok(crate::cache::http::not_modified(&cached.etag));
    }
    Ok(crate::cache::http::json_cached(
        cached.json,
        &cached.etag,
        cached.outcome,
    ))
}

async fn load_position_search(
    state: &AppState,
    sector: &str,
    term: &str,
    limit: i64,
    offset: i64,
    include_inactive: bool,
) -> AppResult<Value> {
    let rows = sqlx::query(
        r#"SELECT p.id, p.label, p.subtitle, p."fieldPattern", p."typeLabel", p.shared, p."isActive"
           FROM hiring_positions p
           WHERE ($5::bool OR p."isActive")
             AND ($1 = '' OR EXISTS (
               SELECT 1 FROM hiring_sector_positions sp
               WHERE sp."positionId" = p.id AND sp."sectorId" = $1
             ))
             AND ($2 = '' OR p.label ILIKE '%' || $2 || '%' OR p.subtitle ILIKE '%' || $2 || '%'
               OR EXISTS (
                 SELECT 1 FROM hiring_aliases a
                 WHERE a."isActive" AND a."entityType" = 'position' AND a."entityId" = p.id
                   AND a.alias ILIKE '%' || $2 || '%'
               ))
           ORDER BY p.label
           LIMIT $3 OFFSET $4"#,
    )
    .bind(&sector)
    .bind(&term)
    .bind(limit)
    .bind(offset)
    .bind(include_inactive)
    .fetch_all(&state.db)
    .await?;
    let total: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM hiring_positions p
           WHERE ($3::bool OR p."isActive")
             AND ($1 = '' OR EXISTS (
               SELECT 1 FROM hiring_sector_positions sp
               WHERE sp."positionId" = p.id AND sp."sectorId" = $1
             ))
             AND ($2 = '' OR p.label ILIKE '%' || $2 || '%' OR p.subtitle ILIKE '%' || $2 || '%')"#,
    )
    .bind(&sector)
    .bind(&term)
    .bind(include_inactive)
    .fetch_one(&state.db)
    .await?;
    Ok(json!({
        "items": rows.iter().map(position_summary).collect::<Vec<_>>(),
        "total": total,
        "limit": limit,
        "offset": offset,
    }))
}

fn position_summary(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<String,_>("id"),
        "label": row.get::<String,_>("label"),
        "subtitle": row.get::<String,_>("subtitle"),
        "fieldPattern": row.get::<String,_>("fieldPattern"),
        "typeLabel": row.get::<String,_>("typeLabel"),
        "shared": row.get::<bool,_>("shared"),
        "isActive": row.try_get::<bool,_>("isActive").unwrap_or(true),
    })
}

async fn position_detail(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> AppResult<Response> {
    let suffix = format!("posdetail:{id}");
    let if_none = headers
        .get(axum::http::header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let db_state = state.clone();
    let pid = id.clone();
    let cached = crate::cache::read_through(
        &state,
        crate::cache::versions::Domain::HiringMaster,
        &suffix,
        state.cache.hiring_master_ttl_secs,
        None,
        if_none,
        || {
            let state = db_state.clone();
            let pid = pid.clone();
            Box::pin(async move { load_position_detail(&state, &pid).await })
        },
    )
    .await?;
    if cached.json.is_null() {
        return Ok(crate::cache::http::not_modified(&cached.etag));
    }
    Ok(crate::cache::http::json_cached(
        cached.json,
        &cached.etag,
        cached.outcome,
    ))
}

async fn load_position_detail(state: &AppState, id: &str) -> AppResult<Value> {
    let row = sqlx::query(
        r#"SELECT id, label, subtitle, "fieldPattern", "typeLabel", shared, "isActive"
           FROM hiring_positions WHERE id = $1"#,
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Position not found".into()))?;
    let sectors = sqlx::query(
        r#"SELECT s.id, s.label FROM hiring_sectors s
           JOIN hiring_sector_positions sp ON sp."sectorId" = s.id
           WHERE sp."positionId" = $1 AND s."isActive" ORDER BY s."sortOrder""#,
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    let types = sqlx::query(
        r#"SELECT id, label, "isActive" FROM hiring_specializations
           WHERE "positionId" = $1 ORDER BY "sortOrder", label"#,
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    let skills = sqlx::query(
        r#"SELECT s.id, s.label, ps.tier, s."isActive" FROM hiring_skills s
           JOIN hiring_position_skills ps ON ps."skillId" = s.id
           WHERE ps."positionId" = $1
           ORDER BY CASE ps.tier WHEN 'suggested' THEN 0 ELSE 1 END, ps."sortOrder", s.label"#,
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    Ok(json!({
        "id": row.get::<String,_>("id"),
        "label": row.get::<String,_>("label"),
        "subtitle": row.get::<String,_>("subtitle"),
        "fieldPattern": row.get::<String,_>("fieldPattern"),
        "typeLabel": row.get::<String,_>("typeLabel"),
        "shared": row.get::<bool,_>("shared"),
        "isActive": row.get::<bool,_>("isActive"),
        "sectors": sectors.iter().map(|r| json!({"id": r.get::<String,_>("id"), "label": r.get::<String,_>("label")})).collect::<Vec<_>>(),
        "specializations": types.iter().map(|r| json!({"id": r.get::<String,_>("id"), "label": r.get::<String,_>("label"), "isActive": r.get::<bool,_>("isActive")})).collect::<Vec<_>>(),
        "skills": skills.iter().map(|r| json!({"id": r.get::<String,_>("id"), "label": r.get::<String,_>("label"), "tier": r.get::<String,_>("tier"), "isActive": r.get::<bool,_>("isActive")})).collect::<Vec<_>>(),
    }))
}

fn hiring_audit(
    user: &AuthUser,
    section: &'static str,
    entity_type: &'static str,
    entity_id: &str,
    action: &'static str,
    detail: Value,
) -> crate::master_audit::AuditEvent {
    crate::master_audit::AuditEvent {
        section,
        entity_type,
        entity_id: entity_id.to_string(),
        action,
        actor_user_id: user.user_id.clone(),
        before: None,
        after: Some(crate::master_audit::redact_secrets(detail)),
    }
}

async fn commit_hiring_cache_tx(
    tx: sqlx::Transaction<'_, sqlx::Postgres>,
    audit: crate::master_audit::AuditEvent,
) -> AppResult<()> {
    crate::master_audit::commit_with_audit(
        tx,
        audit,
        crate::cache::versions::Domain::HiringMaster,
    )
    .await
}

async fn commit_location_cache_tx(
    tx: sqlx::Transaction<'_, sqlx::Postgres>,
    audit: crate::master_audit::AuditEvent,
) -> AppResult<()> {
    crate::master_audit::commit_with_audit(
        tx,
        audit,
        crate::cache::versions::Domain::LocationMaster,
    )
    .await
}

async fn import_bundled(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let catalog: Value = serde_json::from_str(BUNDLED)
        .map_err(|_| AppError::BadRequest("Bundled catalogue is invalid".into()))?;
    let mut tx = state.db.begin().await?;
    let mut sectors = 0i64;
    let mut positions = 0i64;
    let mut bundled_position_ids = std::collections::HashSet::new();
    for (index, sector) in catalog["sectors"].as_array().into_iter().flatten().enumerate() {
        sqlx::query(
            r#"INSERT INTO hiring_sectors (id, label, subtitle, icon, color, "sortOrder")
               VALUES ($1,$2,$3,$4,$5,$6)
               ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, subtitle=EXCLUDED.subtitle,
                 icon=EXCLUDED.icon, color=EXCLUDED.color, "sortOrder"=EXCLUDED."sortOrder", "updatedAt"=NOW()"#,
        )
        .bind(text(sector, "id"))
        .bind(text(sector, "label"))
        .bind(text(sector, "subtitle"))
        .bind(text(sector, "icon"))
        .bind(text(sector, "color"))
        .bind(index as i32)
        .execute(&mut *tx)
        .await?;
        sectors += 1;
    }
    for item in catalog["employmentTypes"].as_array().into_iter().flatten().enumerate() {
        let (index, row) = item;
        sqlx::query(
            r#"INSERT INTO hiring_employment_types (code, label, "sortOrder") VALUES ($1,$2,$3)
               ON CONFLICT (code) DO UPDATE SET label=EXCLUDED.label, "sortOrder"=EXCLUDED."sortOrder""#,
        )
        .bind(text(row, "code"))
        .bind(text(row, "label"))
        .bind(index as i32)
        .execute(&mut *tx)
        .await?;
    }
    for item in catalog["salaryPeriods"].as_array().into_iter().flatten().enumerate() {
        let (index, row) = item;
        sqlx::query(
            r#"INSERT INTO hiring_salary_periods (code, label, "sortOrder") VALUES ($1,$2,$3)
               ON CONFLICT (code) DO UPDATE SET label=EXCLUDED.label, "sortOrder"=EXCLUDED."sortOrder""#,
        )
        .bind(text(row, "code"))
        .bind(text(row, "label"))
        .bind(index as i32)
        .execute(&mut *tx)
        .await?;
    }
    for item in catalog["qualifications"].as_array().into_iter().flatten().enumerate() {
        let (index, row) = item;
        sqlx::query(
            r#"INSERT INTO hiring_qualifications (id, label, rank, professional, "sortOrder")
               VALUES ($1,$2,$3,$4,$5)
               ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, rank=EXCLUDED.rank,
                 professional=EXCLUDED.professional, "sortOrder"=EXCLUDED."sortOrder""#,
        )
        .bind(text(row, "id"))
        .bind(text(row, "label"))
        .bind(row.get("rank").and_then(|v| v.as_i64()).map(|n| n as i32))
        .bind(row.get("professional").and_then(|v| v.as_bool()).unwrap_or(false))
        .bind(index as i32)
        .execute(&mut *tx)
        .await?;
    }
    for position in catalog["positions"].as_array().into_iter().flatten() {
        let id = text(position, "id");
        if !id.is_empty() {
            bundled_position_ids.insert(id.clone());
        }
        sqlx::query(
            r#"INSERT INTO hiring_positions (id, label, subtitle, "fieldPattern", "typeLabel", shared, "isActive")
               VALUES ($1,$2,$3,$4,$5,$6,true)
               ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, subtitle=EXCLUDED.subtitle,
                 "fieldPattern"=EXCLUDED."fieldPattern", "typeLabel"=EXCLUDED."typeLabel",
                 shared=EXCLUDED.shared, "isActive"=true, "updatedAt"=NOW()"#,
        )
        .bind(&id)
        .bind(text(position, "label"))
        .bind(text(position, "subtitle"))
        .bind(text(position, "fieldPattern"))
        .bind(text(position, "typeLabel"))
        .bind(position.get("shared").and_then(|v| v.as_bool()).unwrap_or(false))
        .execute(&mut *tx)
        .await?;
        for sector_id in position["sectorIds"].as_array().into_iter().flatten() {
            sqlx::query(
                r#"INSERT INTO hiring_sector_positions ("sectorId","positionId") VALUES ($1,$2)
                   ON CONFLICT DO NOTHING"#,
            )
            .bind(sector_id.as_str().unwrap_or(""))
            .bind(&id)
            .execute(&mut *tx)
            .await?;
        }
        for (index, spec) in position["specializations"].as_array().into_iter().flatten().enumerate() {
            sqlx::query(
                r#"INSERT INTO hiring_specializations (id, "positionId", label, "sortOrder")
                   VALUES ($1,$2,$3,$4)
                   ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, "sortOrder"=EXCLUDED."sortOrder""#,
            )
            .bind(text(spec, "id"))
            .bind(&id)
            .bind(text(spec, "label"))
            .bind(index as i32)
            .execute(&mut *tx)
            .await?;
        }
        for (index, skill) in position["skills"].as_array().into_iter().flatten().enumerate() {
            let skill_id = text(skill, "id");
            sqlx::query(
                r#"INSERT INTO hiring_skills (id, label) VALUES ($1,$2)
                   ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label"#,
            )
            .bind(&skill_id)
            .bind(text(skill, "label"))
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                r#"INSERT INTO hiring_position_skills ("positionId","skillId",tier,"sortOrder")
                   VALUES ($1,$2,$3,$4)
                   ON CONFLICT ("positionId","skillId") DO UPDATE SET tier=EXCLUDED.tier, "sortOrder"=EXCLUDED."sortOrder""#,
            )
            .bind(&id)
            .bind(&skill_id)
            .bind(skill.get("tier").and_then(|v| v.as_str()).unwrap_or("suggested"))
            .bind(index as i32)
            .execute(&mut *tx)
            .await?;
        }
        positions += 1;
    }
    for alias in catalog["aliases"].as_array().into_iter().flatten() {
        sqlx::query(
            r#"INSERT INTO hiring_aliases ("entityType","entityId",alias) VALUES ($1,$2,$3)
               ON CONFLICT ("entityType","entityId",alias) DO NOTHING"#,
        )
        .bind(text(alias, "entityType"))
        .bind(text(alias, "entityId"))
        .bind(text(alias, "alias"))
        .execute(&mut *tx)
        .await?;
    }
    for item in catalog
        .get("languages")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .enumerate()
    {
        let (index, row) = item;
        sqlx::query(
            r#"INSERT INTO hiring_languages (id, label, "quickPick", "sortOrder")
               VALUES ($1,$2,$3,$4)
               ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, "quickPick"=EXCLUDED."quickPick",
                 "sortOrder"=EXCLUDED."sortOrder", "updatedAt"=NOW()"#,
        )
        .bind(text(row, "id"))
        .bind(text(row, "label"))
        .bind(row.get("quickPick").and_then(|v| v.as_bool()).unwrap_or(false))
        .bind(row.get("sortOrder").and_then(|v| v.as_i64()).unwrap_or(index as i64) as i32)
        .execute(&mut *tx)
        .await?;
    }
    let (legacy_aliases, legacy_retired) =
        apply_legacy_catalogue(&mut tx, &bundled_position_ids).await?;
    let version = catalog
        .get("version")
        .and_then(|v| v.as_str())
        .map(String::from)
        .unwrap_or_else(bundled_version);
    crate::master_audit::insert_in_tx(
        &mut tx,
        &hiring_audit(
            &user,
            "hiring_catalogue",
            "catalogue",
            "bundled",
            "import",
            json!({"sectors": sectors, "positions": positions, "version": version}),
        ),
    )
    .await?;
    let cache_version = crate::cache::versions::bump_in_tx(
        &mut tx,
        crate::cache::versions::Domain::HiringMaster,
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({
        "imported": true,
        "sectors": sectors,
        "positions": positions,
        "version": version,
        "cacheVersion": cache_version,
        "legacyAliases": legacy_aliases,
        "legacyRetired": legacy_retired,
    })))
}

async fn apply_legacy_catalogue(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    bundled_ids: &std::collections::HashSet<String>,
) -> AppResult<(i64, i64)> {
    let legacy: Value =
        serde_json::from_str(LEGACY_MAP).unwrap_or_else(|_| json!({"mappings": []}));
    let mut aliases_written = 0i64;
    let mut retired = 0i64;
    for item in legacy
        .get("mappings")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
    {
        let from = item
            .get("fromPositionId")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        let to = item
            .get("toPositionId")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim();
        if from.is_empty() || to.is_empty() {
            continue;
        }
        if from != to {
            let result = sqlx::query(
                r#"INSERT INTO hiring_aliases ("entityType","entityId",alias) VALUES ('position',$1,$2)
                   ON CONFLICT ("entityType","entityId",alias) DO NOTHING"#,
            )
            .bind(to)
            .bind(from)
            .execute(&mut **tx)
            .await?;
            aliases_written += result.rows_affected() as i64;

            let prefix = format!("{from}--");
            let new_prefix = format!("{to}--");
            let old_specs = sqlx::query(
                r#"SELECT id FROM hiring_specializations WHERE "positionId" = $1"#,
            )
            .bind(from)
            .fetch_all(&mut **tx)
            .await?;
            for row in old_specs {
                let old_id: String = row.get("id");
                let Some(suffix) = old_id.strip_prefix(&prefix) else {
                    continue;
                };
                let new_id = format!("{new_prefix}{suffix}");
                let mapped: bool = sqlx::query_scalar(
                    r#"SELECT EXISTS(SELECT 1 FROM hiring_specializations WHERE id = $1)"#,
                )
                .bind(&new_id)
                .fetch_one(&mut **tx)
                .await?;
                if !mapped {
                    continue;
                }
                let result = sqlx::query(
                    r#"INSERT INTO hiring_aliases ("entityType","entityId",alias) VALUES ('specialization',$1,$2)
                       ON CONFLICT ("entityType","entityId",alias) DO NOTHING"#,
                )
                .bind(&new_id)
                .bind(&old_id)
                .execute(&mut **tx)
                .await?;
                aliases_written += result.rows_affected() as i64;
            }
        }
        if !bundled_ids.contains(from) {
            let result = sqlx::query(
                r#"UPDATE hiring_positions SET "isActive" = false, "updatedAt" = NOW() WHERE id = $1"#,
            )
            .bind(from)
            .execute(&mut **tx)
            .await?;
            if result.rows_affected() > 0 {
                retired += 1;
            }
        }
    }
    Ok((aliases_written, retired))
}

async fn create_language(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    if id.is_empty() {
        return Err(AppError::BadRequest("Language id is required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_languages (id, label, "quickPick", "sortOrder") VALUES ($1,$2,$3,$4)"#,
    )
    .bind(&id)
    .bind(text(&body, "label"))
    .bind(body.get("quickPick").and_then(|v| v.as_bool()).unwrap_or(false))
    .bind(body.get("sortOrder").and_then(|v| v.as_i64()).unwrap_or(0) as i32)
    .execute(&mut *tx)
    .await?;
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "language", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_language(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE hiring_languages SET label = COALESCE($2, label),
           "quickPick" = COALESCE($3, "quickPick"), "isActive" = COALESCE($4, "isActive"), "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(&id)
    .bind(body.get("label").and_then(|v| v.as_str()))
    .bind(body.get("quickPick").and_then(|v| v.as_bool()))
    .bind(body.get("isActive").and_then(|v| v.as_bool()))
    .execute(&mut *tx)
    .await?;
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "language", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

fn text(value: &Value, key: &str) -> String {
    value.get(key).and_then(|v| v.as_str()).unwrap_or("").trim().to_string()
}

async fn create_sector(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    let label = text(&body, "label");
    if id.is_empty() || label.is_empty() {
        return Err(AppError::BadRequest("Sector id and label are required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_sectors (id, label, subtitle, icon, color) VALUES ($1,$2,$3,$4,$5)"#,
    )
    .bind(&id)
    .bind(&label)
    .bind(text(&body, "subtitle"))
    .bind(text(&body, "icon"))
    .bind(text(&body, "color"))
    .execute(&mut *tx)
    .await?;
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "sector", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_sector(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE hiring_sectors SET
             label = COALESCE($2, label),
             subtitle = COALESCE($3, subtitle),
             "isActive" = COALESCE($4, "isActive"),
             "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(&id)
    .bind(body.get("label").and_then(|v| v.as_str()))
    .bind(body.get("subtitle").and_then(|v| v.as_str()))
    .bind(body.get("isActive").and_then(|v| v.as_bool()))
    .execute(&mut *tx)
    .await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "sector", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn create_position(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    let label = text(&body, "label");
    if id.is_empty() || label.is_empty() {
        return Err(AppError::BadRequest("Position id and label are required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_positions (id, label, subtitle, "fieldPattern", "typeLabel", shared)
           VALUES ($1,$2,$3,$4,$5,$6)"#,
    )
    .bind(&id)
    .bind(&label)
    .bind(text(&body, "subtitle"))
    .bind(body.get("fieldPattern").and_then(|v| v.as_str()).unwrap_or("typeChips"))
    .bind(body.get("typeLabel").and_then(|v| v.as_str()).unwrap_or("Type"))
    .bind(body.get("shared").and_then(|v| v.as_bool()).unwrap_or(false))
    .execute(&mut *tx)
    .await?;
    if let Some(sector_id) = body.get("sectorId").and_then(|v| v.as_str()) {
        sqlx::query(
            r#"INSERT INTO hiring_sector_positions ("sectorId","positionId") VALUES ($1,$2) ON CONFLICT DO NOTHING"#,
        )
        .bind(sector_id)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    }
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "position", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_position(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE hiring_positions SET
             label = COALESCE($2, label),
             subtitle = COALESCE($3, subtitle),
             "isActive" = COALESCE($4, "isActive"),
             "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(&id)
    .bind(body.get("label").and_then(|v| v.as_str()))
    .bind(body.get("subtitle").and_then(|v| v.as_str()))
    .bind(body.get("isActive").and_then(|v| v.as_bool()))
    .execute(&mut *tx)
    .await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "position", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn create_specialization(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    if id.is_empty() {
        return Err(AppError::BadRequest("Specialization id is required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_specializations (id, "positionId", label) VALUES ($1,$2,$3)"#,
    )
    .bind(&id)
    .bind(text(&body, "positionId"))
    .bind(text(&body, "label"))
    .execute(&mut *tx)
    .await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "specialization", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_active_specialization(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE hiring_specializations SET label = COALESCE($2, label), "isActive" = COALESCE($3, "isActive") WHERE id = $1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "specialization", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn create_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    if id.is_empty() {
        return Err(AppError::BadRequest("Skill id is required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"INSERT INTO hiring_skills (id, label) VALUES ($1,$2) ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label"#)
        .bind(&id).bind(text(&body, "label")).execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "skill", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE hiring_skills SET label = COALESCE($2, label), "isActive" = COALESCE($3, "isActive") WHERE id = $1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "skill", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn link_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_position_skills ("positionId","skillId",tier) VALUES ($1,$2,$3)
           ON CONFLICT ("positionId","skillId") DO UPDATE SET tier=EXCLUDED.tier"#,
    )
    .bind(text(&body, "positionId"))
    .bind(text(&body, "skillId"))
    .bind(body.get("tier").and_then(|v| v.as_str()).unwrap_or("suggested"))
    .execute(&mut *tx)
    .await?;
    
    let position_id = text(&body, "positionId");
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "position_skill", &position_id, "link", body.clone())).await?;
    Ok(Json(json!({"linked": true})))
}

async fn create_qualification(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    if id.is_empty() {
        return Err(AppError::BadRequest("Qualification id is required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_qualifications (id, label, rank, professional) VALUES ($1,$2,$3,$4)"#,
    )
    .bind(&id)
    .bind(text(&body, "label"))
    .bind(body.get("rank").and_then(|v| v.as_i64()).map(|n| n as i32))
    .bind(body.get("professional").and_then(|v| v.as_bool()).unwrap_or(false))
    .execute(&mut *tx)
    .await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "qualification", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_qualification(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE hiring_qualifications SET label=COALESCE($2,label), "isActive"=COALESCE($3,"isActive") WHERE id=$1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "qualification", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_employment(
    State(state): State<AppState>,
    user: AuthUser,
    Path(code): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE hiring_employment_types SET label=COALESCE($2,label), "isActive"=COALESCE($3,"isActive") WHERE code=$1"#)
        .bind(&code)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "employment_type", &code, "update", body.clone())).await?;
    Ok(Json(json!({"code": code})))
}

async fn create_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    let id: uuid::Uuid = sqlx::query_scalar(
        r#"INSERT INTO hiring_aliases ("entityType","entityId",alias) VALUES ($1,$2,$3) RETURNING id"#,
    )
    .bind(text(&body, "entityType"))
    .bind(text(&body, "entityId"))
    .bind(text(&body, "alias"))
    .fetch_one(&mut *tx)
    .await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "alias", &id.to_string(), "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(r#"UPDATE hiring_aliases SET "isActive"=COALESCE($2,"isActive") WHERE id=$1"#)
        .bind(uuid::Uuid::parse_str(&id)?)
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&mut *tx).await?;
    
    commit_hiring_cache_tx(tx, hiring_audit(&user, "hiring_catalogue", "alias", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn admin_list_locations(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let limit = q.limit.unwrap_or(30).clamp(1, 100);
    let offset = q.offset.unwrap_or(0).max(0);
    let term = q.q.unwrap_or_default().trim().to_string();
    let include_inactive = q.include_inactive.unwrap_or(true);
    let rows = if term.chars().count() >= 2 {
        sqlx::query(
            r#"SELECT id, name, kind, "stateName", "districtName", source, "isActive", lat, lng
               FROM hiring_locations
               WHERE ($4::bool OR "isActive")
                 AND (
                   name ILIKE '%' || $1 || '%'
                   OR "districtName" ILIKE '%' || $1 || '%'
                   OR "stateName" ILIKE '%' || $1 || '%'
                 )
               ORDER BY "stateName", "districtName", name
               LIMIT $2 OFFSET $3"#,
        )
        .bind(&term)
        .bind(limit)
        .bind(offset)
        .bind(include_inactive)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            r#"SELECT id, name, kind, "stateName", "districtName", source, "isActive", lat, lng
               FROM hiring_locations
               WHERE ($3::bool OR "isActive") AND kind = 'PLACE'
               ORDER BY "updatedAt" DESC
               LIMIT $1 OFFSET $2"#,
        )
        .bind(limit)
        .bind(offset)
        .bind(include_inactive)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(json!({
        "items": rows.iter().map(|r| json!({
            "id": r.get::<String,_>("id"),
            "name": r.get::<String,_>("name"),
            "kind": r.get::<String,_>("kind"),
            "stateName": r.get::<String,_>("stateName"),
            "districtName": r.get::<String,_>("districtName"),
            "source": r.get::<String,_>("source"),
            "isActive": r.get::<bool,_>("isActive"),
            "lat": r.get::<Option<f64>,_>("lat"),
            "lng": r.get::<Option<f64>,_>("lng"),
        })).collect::<Vec<_>>(),
        "limit": limit,
        "offset": offset,
    })))
}

async fn search_locations(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<PageQuery>,
) -> AppResult<Response> {
    let limit = q.limit.unwrap_or(20).clamp(1, 40);
    let offset = q.offset.unwrap_or(0).max(0);
    let term = q.q.unwrap_or_default().trim().to_string();
    if term.chars().count() < 2 {
        return Ok(crate::cache::http::json_cached(
            json!({"items": [], "total": 0, "limit": limit, "offset": offset}),
            ""empty"",
            crate::cache::CacheOutcome::Miss,
        ));
    }
    if term.chars().count() > 80 {
        return Err(AppError::BadRequest("Search query is too long".into()));
    }
    let state_filter = q.sector_id.as_deref().unwrap_or("");
    let district_filter = q.include_inactive.map(|v| if v { "1" } else { "0" }).unwrap_or("0");
    let norm = crate::cache::normalize_search_query(&term);
    let suffix = format!("loc:{state_filter}:{district_filter}:{norm}:{limit}:{offset}");
    let if_none = headers
        .get(axum::http::header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let db_state = state.clone();
    let term_key = term.clone();
    let cached = crate::cache::read_through(
        &state,
        crate::cache::versions::Domain::LocationMaster,
        &suffix,
        state.cache.location_search_ttl_secs,
        Some(state.cache.location_empty_ttl_secs),
        if_none,
        || {
            let state = db_state.clone();
            let term = term_key.clone();
            Box::pin(async move { load_location_search(&state, &term, limit, offset).await })
        },
    )
    .await?;
    if cached.json.is_null() {
        return Ok(crate::cache::http::not_modified(&cached.etag));
    }
    Ok(crate::cache::http::json_cached(
        cached.json,
        &cached.etag,
        cached.outcome,
    ))
}

async fn load_location_search(
    state: &AppState,
    term: &str,
    limit: i64,
    offset: i64,
) -> AppResult<Value> {
    let rows = sqlx::query(
        r#"SELECT l.id, l.name, l.kind, l."stateName", l."districtName", l.lat, l.lng,
                  CASE
                    WHEN lower(l.name) = lower($1) THEN 'EXACT'
                    WHEN EXISTS (
                      SELECT 1 FROM hiring_location_aliases a
                      WHERE a."locationId" = l.id AND lower(a.alias) = lower($1)
                    ) THEN 'ALIAS'
                    ELSE 'SUGGESTION'
                  END AS "matchKind",
                  similarity(l.name, $1) AS sim
           FROM hiring_locations l
           WHERE l."isActive" AND l.kind = 'PLACE'
             AND (
               l.name ILIKE '%' || $1 || '%'
               OR l."districtName" ILIKE '%' || $1 || '%'
               OR l."stateName" ILIKE '%' || $1 || '%'
               OR (l.name || ' ' || l."districtName" || ' ' || l."stateName") ILIKE '%' || $1 || '%'
               OR similarity(l.name, $1) > 0.35
               OR EXISTS (
                 SELECT 1 FROM hiring_location_aliases a
                 WHERE a."locationId" = l.id AND (a.alias ILIKE '%' || $1 || '%' OR similarity(a.alias, $1) > 0.4)
               )
             )
           ORDER BY CASE
             WHEN lower(l.name) = lower($1) THEN 0
             WHEN EXISTS (SELECT 1 FROM hiring_location_aliases a WHERE a."locationId"=l.id AND lower(a.alias)=lower($1)) THEN 1
             ELSE 2 END,
             similarity(l.name, $1) DESC, l.name
           LIMIT $2 OFFSET $3"#,
    )
    .bind(&term)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;
    Ok(json!({
        "items": rows.iter().map(|r| json!({
            "id": r.get::<String,_>("id"),
            "name": r.get::<String,_>("name"),
            "kind": r.get::<String,_>("kind"),
            "stateName": r.get::<String,_>("stateName"),
            "districtName": r.get::<String,_>("districtName"),
            "lat": r.get::<Option<f64>,_>("lat"),
            "lng": r.get::<Option<f64>,_>("lng"),
            "matchKind": r.get::<String,_>("matchKind"),
            "needsConfirmation": r.get::<String,_>("matchKind") == "SUGGESTION",
        })).collect::<Vec<_>>(),
        "limit": limit,
        "offset": offset,
    }))
}

async fn location_detail(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let row = sqlx::query(
        r#"SELECT id, name, kind, "stateName", "districtName", "stateId", "districtId", lat, lng, "isActive"
           FROM hiring_locations WHERE id=$1"#,
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Location not found".into()))?;
    Ok(Json(json!({
        "id": row.get::<String,_>("id"),
        "name": row.get::<String,_>("name"),
        "kind": row.get::<String,_>("kind"),
        "stateName": row.get::<String,_>("stateName"),
        "districtName": row.get::<String,_>("districtName"),
        "stateId": row.get::<Option<String>,_>("stateId"),
        "districtId": row.get::<Option<String>,_>("districtId"),
        "lat": row.get::<Option<f64>,_>("lat"),
        "lng": row.get::<Option<f64>,_>("lng"),
        "isActive": row.get::<bool,_>("isActive"),
    })))
}

async fn create_location(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id = text(&body, "id");
    if id.is_empty() || text(&body, "name").is_empty() {
        return Err(AppError::BadRequest("Location id and name are required".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_locations (id, kind, name, "parentId", "stateId", "districtId", "stateName", "districtName", lat, lng, source, "sourceKey")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)"#,
    )
    .bind(&id)
    .bind(body.get("kind").and_then(|v| v.as_str()).unwrap_or("PLACE"))
    .bind(text(&body, "name"))
    .bind(body.get("parentId").and_then(|v| v.as_str()))
    .bind(body.get("stateId").and_then(|v| v.as_str()))
    .bind(body.get("districtId").and_then(|v| v.as_str()))
    .bind(text(&body, "stateName"))
    .bind(text(&body, "districtName"))
    .bind(body.get("lat").and_then(|v| v.as_f64()))
    .bind(body.get("lng").and_then(|v| v.as_f64()))
    .bind(text(&body, "source"))
    .bind(text(&body, "sourceKey"))
    .execute(&mut *tx)
    .await?;
    
    commit_location_cache_tx(tx, hiring_audit(&user, "location_master", "location", &id, "create", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_location(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"UPDATE hiring_locations SET name=COALESCE($2,name), "isActive"=COALESCE($3,"isActive"), "updatedAt"=NOW() WHERE id=$1"#,
    )
    .bind(&id)
    .bind(body.get("name").and_then(|v| v.as_str()))
    .bind(body.get("isActive").and_then(|v| v.as_bool()))
    .execute(&mut *tx)
    .await?;
    
    commit_location_cache_tx(tx, hiring_audit(&user, "location_master", "location", &id, "update", body.clone())).await?;
    Ok(Json(json!({"id": id})))
}

async fn create_location_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        r#"INSERT INTO hiring_location_aliases ("locationId", alias) VALUES ($1,$2) ON CONFLICT DO NOTHING"#,
    )
    .bind(&id)
    .bind(text(&body, "alias"))
    .execute(&mut *tx)
    .await?;
    
    commit_location_cache_tx(tx, hiring_audit(&user, "location_master", "location_alias", &id, "create", body.clone())).await?;
    Ok(Json(json!({"locationId": id})))
}
