use axum::{
    extract::{Path, Query, State},
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
}

pub fn location_routes() -> Router<AppState> {
    Router::new()
        .route("/search", get(search_locations))
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

async fn snapshot(State(state): State<AppState>, Query(q): Query<PageQuery>) -> AppResult<Json<Value>> {
    let include_inactive = q.include_inactive.unwrap_or(false);
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
    Ok(Json(json!({
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
    })))
}

async fn search_positions(
    State(state): State<AppState>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Value>> {
    let limit = q.limit.unwrap_or(30).clamp(1, 100);
    let offset = q.offset.unwrap_or(0).max(0);
    let term = q.q.unwrap_or_default().trim().to_string();
    let sector = q.sector_id.unwrap_or_default();
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
    .bind(q.include_inactive.unwrap_or(false))
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
    .bind(q.include_inactive.unwrap_or(false))
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({
        "items": rows.iter().map(position_summary).collect::<Vec<_>>(),
        "total": total,
        "limit": limit,
        "offset": offset,
    })))
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
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
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
    Ok(Json(json!({
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
    })))
}

async fn import_bundled(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let catalog: Value = serde_json::from_str(BUNDLED)
        .map_err(|_| AppError::BadRequest("Bundled catalogue is invalid".into()))?;
    let mut tx = state.db.begin().await?;
    let mut sectors = 0i64;
    let mut positions = 0i64;
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
        sqlx::query(
            r#"INSERT INTO hiring_positions (id, label, subtitle, "fieldPattern", "typeLabel", shared)
               VALUES ($1,$2,$3,$4,$5,$6)
               ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label, subtitle=EXCLUDED.subtitle,
                 "fieldPattern"=EXCLUDED."fieldPattern", "typeLabel"=EXCLUDED."typeLabel",
                 shared=EXCLUDED.shared, "updatedAt"=NOW()"#,
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
    tx.commit().await?;
    Ok(Json(json!({"imported": true, "sectors": sectors, "positions": positions})))
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
    sqlx::query(
        r#"INSERT INTO hiring_sectors (id, label, subtitle, icon, color) VALUES ($1,$2,$3,$4,$5)"#,
    )
    .bind(&id)
    .bind(&label)
    .bind(text(&body, "subtitle"))
    .bind(text(&body, "icon"))
    .bind(text(&body, "color"))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_sector(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
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
    .execute(&state.db)
    .await?;
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
    .execute(&state.db)
    .await?;
    if let Some(sector_id) = body.get("sectorId").and_then(|v| v.as_str()) {
        sqlx::query(
            r#"INSERT INTO hiring_sector_positions ("sectorId","positionId") VALUES ($1,$2) ON CONFLICT DO NOTHING"#,
        )
        .bind(sector_id)
        .bind(&id)
        .execute(&state.db)
        .await?;
    }
    Ok(Json(json!({"id": id})))
}

async fn patch_position(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
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
    .execute(&state.db)
    .await?;
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
    sqlx::query(
        r#"INSERT INTO hiring_specializations (id, "positionId", label) VALUES ($1,$2,$3)"#,
    )
    .bind(&id)
    .bind(text(&body, "positionId"))
    .bind(text(&body, "label"))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_active_specialization(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(r#"UPDATE hiring_specializations SET label = COALESCE($2, label), "isActive" = COALESCE($3, "isActive") WHERE id = $1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&state.db).await?;
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
    sqlx::query(r#"INSERT INTO hiring_skills (id, label) VALUES ($1,$2) ON CONFLICT (id) DO UPDATE SET label=EXCLUDED.label"#)
        .bind(&id).bind(text(&body, "label")).execute(&state.db).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(r#"UPDATE hiring_skills SET label = COALESCE($2, label), "isActive" = COALESCE($3, "isActive") WHERE id = $1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&state.db).await?;
    Ok(Json(json!({"id": id})))
}

async fn link_skill(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(
        r#"INSERT INTO hiring_position_skills ("positionId","skillId",tier) VALUES ($1,$2,$3)
           ON CONFLICT ("positionId","skillId") DO UPDATE SET tier=EXCLUDED.tier"#,
    )
    .bind(text(&body, "positionId"))
    .bind(text(&body, "skillId"))
    .bind(body.get("tier").and_then(|v| v.as_str()).unwrap_or("suggested"))
    .execute(&state.db)
    .await?;
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
    sqlx::query(
        r#"INSERT INTO hiring_qualifications (id, label, rank, professional) VALUES ($1,$2,$3,$4)"#,
    )
    .bind(&id)
    .bind(text(&body, "label"))
    .bind(body.get("rank").and_then(|v| v.as_i64()).map(|n| n as i32))
    .bind(body.get("professional").and_then(|v| v.as_bool()).unwrap_or(false))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_qualification(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(r#"UPDATE hiring_qualifications SET label=COALESCE($2,label), "isActive"=COALESCE($3,"isActive") WHERE id=$1"#)
        .bind(&id)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&state.db).await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_employment(
    State(state): State<AppState>,
    user: AuthUser,
    Path(code): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(r#"UPDATE hiring_employment_types SET label=COALESCE($2,label), "isActive"=COALESCE($3,"isActive") WHERE code=$1"#)
        .bind(&code)
        .bind(body.get("label").and_then(|v| v.as_str()))
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&state.db).await?;
    Ok(Json(json!({"code": code})))
}

async fn create_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    let id: uuid::Uuid = sqlx::query_scalar(
        r#"INSERT INTO hiring_aliases ("entityType","entityId",alias) VALUES ($1,$2,$3) RETURNING id"#,
    )
    .bind(text(&body, "entityType"))
    .bind(text(&body, "entityId"))
    .bind(text(&body, "alias"))
    .fetch_one(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(r#"UPDATE hiring_aliases SET "isActive"=COALESCE($2,"isActive") WHERE id=$1"#)
        .bind(uuid::Uuid::parse_str(&id)?)
        .bind(body.get("isActive").and_then(|v| v.as_bool()))
        .execute(&state.db).await?;
    Ok(Json(json!({"id": id})))
}

async fn search_locations(
    State(state): State<AppState>,
    Query(q): Query<PageQuery>,
) -> AppResult<Json<Value>> {
    let limit = q.limit.unwrap_or(20).clamp(1, 40);
    let offset = q.offset.unwrap_or(0).max(0);
    let term = q.q.unwrap_or_default().trim().to_string();
    if term.chars().count() < 2 {
        return Ok(Json(json!({"items": [], "total": 0, "limit": limit, "offset": offset})));
    }
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
    Ok(Json(json!({
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
    })))
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
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn patch_location(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(
        r#"UPDATE hiring_locations SET name=COALESCE($2,name), "isActive"=COALESCE($3,"isActive"), "updatedAt"=NOW() WHERE id=$1"#,
    )
    .bind(&id)
    .bind(body.get("name").and_then(|v| v.as_str()))
    .bind(body.get("isActive").and_then(|v| v.as_bool()))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"id": id})))
}

async fn create_location_alias(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "master-entries")?;
    sqlx::query(
        r#"INSERT INTO hiring_location_aliases ("locationId", alias) VALUES ($1,$2) ON CONFLICT DO NOTHING"#,
    )
    .bind(&id)
    .bind(text(&body, "alias"))
    .execute(&state.db)
    .await?;
    Ok(Json(json!({"locationId": id})))
}
