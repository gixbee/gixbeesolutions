//! Admin portal: master sections meta, audit history, validated pricing/operational settings.

use axum::{
    extract::{Query, State},
    routing::{get, patch},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::cache::versions::Domain;
use crate::error::{AppError, AppResult};
use crate::master_audit::{self, AuditEvent};
use crate::middleware::auth::{require_admin, require_admin_page, AuthUser};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/meta", get(meta))
        .route("/audit", get(list_audit))
        .route("/settings/pricing", get(get_pricing_settings).patch(patch_pricing_setting))
        .route("/settings/operational", get(get_operational_settings).patch(patch_operational_setting))
        .route("/rental-catalogue-meta", get(rental_catalogue_meta))
        .route("/event-catalogue-meta", get(event_catalogue_meta))
}

#[derive(Deserialize)]
struct AuditQuery {
    section: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
}

async fn meta(user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    Ok(Json(json!({
        "sections": [
            {"id": "hiring_catalogue", "label": "Hiring catalogue", "permission": "master-entries", "cacheDomain": "hiring_master"},
            {"id": "service_catalogue", "label": "Service catalogue", "permission": "master-entries", "cacheDomain": "service_master"},
            {"id": "location_master", "label": "Location master", "permission": "master-entries", "cacheDomain": "location_master"},
            {"id": "serviceable_areas", "label": "Serviceable areas (cities)", "permission": "cities", "cacheDomain": "service_master"},
            {"id": "rental_catalogue", "label": "Rental catalogue choices", "permission": "master-entries", "cacheDomain": "service_master"},
            {"id": "event_catalogue", "label": "Event vendor services", "permission": "master-entries", "cacheDomain": "service_master"},
            {"id": "pricing_policies", "label": "Pricing & policies", "permission": "pricing-policies", "cacheDomain": "service_master"},
            {"id": "operational_settings", "label": "Operational settings", "permission": "operational-settings", "cacheDomain": "service_master"},
            {"id": "content_reasons", "label": "Content & reasons", "permission": "master-entries", "cacheDomain": "service_master"},
        ]
    })))
}

async fn list_audit(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AuditQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let offset = q.offset.unwrap_or(0).max(0);
    let rows = if let Some(section) = q.section.as_deref() {
        sqlx::query(
            r#"SELECT id, section, "entityType", "entityId", action, "actorUserId", "beforeJson", "afterJson", "createdAt"
               FROM master_data_audit WHERE section = $1 ORDER BY "createdAt" DESC LIMIT $2 OFFSET $3"#,
        )
        .bind(section)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            r#"SELECT id, section, "entityType", "entityId", action, "actorUserId", "beforeJson", "afterJson", "createdAt"
               FROM master_data_audit ORDER BY "createdAt" DESC LIMIT $1 OFFSET $2"#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(json!({
        "items": rows.iter().map(|r| json!({
            "id": r.get::<Uuid,_>("id").to_string(),
            "section": r.get::<String,_>("section"),
            "entityType": r.get::<String,_>("entityType"),
            "entityId": r.get::<String,_>("entityId"),
            "action": r.get::<String,_>("action"),
            "actorUserId": r.get::<Uuid,_>("actorUserId").to_string(),
            "before": r.get::<Option<Value>,_>("beforeJson"),
            "after": r.get::<Option<Value>,_>("afterJson"),
            "createdAt": r.get::<chrono::DateTime<chrono::Utc>,_>("createdAt"),
        })).collect::<Vec<_>>(),
        "limit": limit,
        "offset": offset,
    })))
}

#[derive(Clone, Copy)]
struct SettingDef {
    key: &'static str,
    label: &'static str,
    unit: &'static str,
    min: i64,
    max: i64,
    fallback: i64,
    description: &'static str,
}

const PRICING_SETTINGS: &[SettingDef] = &[
    SettingDef {
        key: "seeker_pro_month",
        label: "Jobseeker Pro monthly price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 299,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "seeker_pro_quarter",
        label: "Jobseeker Pro quarterly price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 597,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "seeker_pro_month_days",
        label: "Monthly plan validity",
        unit: "days",
        min: 1,
        max: 365,
        fallback: 30,
        description: "Validity for new purchases or trials.",
    },
    SettingDef {
        key: "seeker_pro_quarter_days",
        label: "Quarterly plan validity",
        unit: "days",
        min: 1,
        max: 365,
        fallback: 90,
        description: "Validity for new purchases or trials.",
    },
    SettingDef {
        key: "seeker_trial_days",
        label: "Jobseeker Pro trial",
        unit: "days",
        min: 0,
        max: 30,
        fallback: 7,
        description: "Validity for new purchases or trials.",
    },
    SettingDef {
        key: "service_standard",
        label: "Service Standard price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 999,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "service_pro",
        label: "Service Pro price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 2499,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "rental_standard",
        label: "Rental Standard price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 699,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "shop_standard",
        label: "Shop Standard price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 499,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "hiring_standard",
        label: "Hiring Standard price",
        unit: "INR",
        min: 0,
        max: 100000,
        fallback: 799,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "business_plan_days",
        label: "Business plan validity",
        unit: "days",
        min: 1,
        max: 365,
        fallback: 30,
        description: "Validity for new purchases or trials.",
    },
    SettingDef {
        key: "service_basic_limit",
        label: "Service Basic listing limit",
        unit: "listings",
        min: 1,
        max: 1000,
        fallback: 1,
        description: "Maximum service listings that can be registered.",
    },
    SettingDef {
        key: "service_standard_limit",
        label: "Service Standard listing limit",
        unit: "listings",
        min: 1,
        max: 1000,
        fallback: 3,
        description: "Maximum service listings that can be registered.",
    },
    SettingDef {
        key: "rental_basic_limit",
        label: "Rental Basic item limit",
        unit: "items",
        min: 1,
        max: 1000,
        fallback: 5,
        description: "Maximum rental items that can be registered.",
    },
    SettingDef {
        key: "shop_basic_limit",
        label: "Shop Basic active offer limit",
        unit: "offers",
        min: 1,
        max: 1000,
        fallback: 3,
        description: "Maximum offers that can be active.",
    },
    SettingDef {
        key: "hiring_basic_limit",
        label: "Hiring Basic active request limit",
        unit: "requests",
        min: 1,
        max: 1000,
        fallback: 3,
        description: "Maximum hiring requests that can be active.",
    },
    SettingDef {
        key: "extra_profile_fee",
        label: "Additional career profile price",
        unit: "INR",
        min: 1,
        max: 100000,
        fallback: 50,
        description: "Price for new orders. Zero hides a plan where allowed.",
    },
    SettingDef {
        key: "extra_profile_days",
        label: "Additional career profile validity",
        unit: "days",
        min: 1,
        max: 365,
        fallback: 30,
        description: "Validity for new purchases or trials.",
    },
    SettingDef {
        key: "job_credit_per_accept",
        label: "Job credit per accept",
        unit: "credits",
        min: 0,
        max: 500,
        fallback: 15,
        description: "Credits deducted when a worker accepts a booking; refunded on customer cancel when applicable.",
    },
    SettingDef {
        key: "go_live_period_fee",
        label: "Go-live period fee",
        unit: "INR",
        min: 0,
        max: 9999,
        fallback: 49,
        description: "Razorpay charge to unlock the next batch of included jobs under the periodic go-live plan.",
    },
    SettingDef {
        key: "instant_petrol_per_km",
        label: "Instant help petrol per km",
        unit: "INR/km",
        min: 0,
        max: 200,
        fallback: 10,
        description: "One-way travel compensation rate for Instant Help bookings.",
    },
    SettingDef {
        key: "late_cancel_compensation_per_km",
        label: "Late cancel compensation per km",
        unit: "INR/km",
        min: 0,
        max: 200,
        fallback: 10,
        description: "Worker travel compensation per km when a customer cancels late.",
    },
    SettingDef {
        key: "late_cancel_compensation_min_inr",
        label: "Late cancel compensation minimum",
        unit: "INR",
        min: 0,
        max: 5000,
        fallback: 49,
        description: "Minimum travel compensation for late customer cancellation.",
    },
    SettingDef {
        key: "late_cancel_compensation_max_inr",
        label: "Late cancel compensation maximum",
        unit: "INR",
        min: 0,
        max: 10000,
        fallback: 299,
        description: "Cap on travel compensation for late customer cancellation.",
    },
];

const OPERATIONAL_SETTINGS: &[SettingDef] = &[
    SettingDef {
        key: "go_live_daily_limit",
        label: "Go-live daily limit",
        unit: "sessions/day",
        min: 0,
        max: 50,
        fallback: 0,
        description: "Max go-live sessions per worker per day. 0 = unlimited.",
    },
    SettingDef {
        key: "go_live_jobs_per_payment",
        label: "Go-live jobs per payment",
        unit: "jobs",
        min: 0,
        max: 100,
        fallback: 3,
        description: "Completed jobs included per go-live period payment. 0 disables the plan.",
    },
];

pub(crate) async fn plan_value(db: &sqlx::PgPool, key: &str) -> AppResult<i32> {
    let def = PRICING_SETTINGS.iter().find(|def| def.key == key)
        .ok_or_else(|| AppError::Internal("Unknown plan setting".into()))?;
    let value: Option<String> = sqlx::query_scalar(
        r#"SELECT value FROM master_entries WHERE type::text = 'CONFIGURATION'
           AND label = $1 AND "isActive" = true ORDER BY id LIMIT 1"#,
    )
    .bind(key)
    .fetch_optional(db)
    .await?;
    Ok(value.and_then(|v| v.parse::<i64>().ok())
        .filter(|v| (def.min..=def.max).contains(v))
        .unwrap_or(def.fallback) as i32)
}

async fn load_config_row(state: &AppState, key: &str) -> AppResult<Option<(Uuid, String, String, bool)>> {
    let row = sqlx::query(
        r#"SELECT id, label, value, "isActive" FROM master_entries
           WHERE type::text = 'CONFIGURATION' AND label = $1 LIMIT 1"#,
    )
    .bind(key)
    .fetch_optional(&state.db)
    .await?;
    Ok(row.map(|r| {
        (
            r.get("id"),
            r.get::<String, _>("label"),
            r.get::<String, _>("value"),
            r.get("isActive"),
        )
    }))
}

fn setting_json(def: SettingDef, row: Option<(Uuid, String, String, bool)>) -> Value {
    let (id, value, active) = match row {
        Some((id, _, v, a)) => (Some(id.to_string()), v, a),
        None => (None, def.fallback.to_string(), true),
    };
    json!({
        "key": def.key,
        "label": def.label,
        "unit": def.unit,
        "description": def.description,
        "min": def.min,
        "max": def.max,
        "fallback": def.fallback,
        "value": value,
        "masterEntryId": id,
        "isActive": active,
        "readOnly": false,
    })
}

async fn get_pricing_settings(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    require_pricing_access(&user)?;
    let mut items = Vec::new();
    for def in PRICING_SETTINGS {
        let row = load_config_row(&state, def.key).await?;
        items.push(setting_json(*def, row));
    }
    items.push(json!({
        "key": "hiring_match_fee_tiers",
        "label": "Smart Hiring vacancy fees",
        "unit": "INR",
        "description": "Tier fees (1→49, 2–5→99, 6–10→199, 11–25→399) are computed in Rust (fee_for_vacancies). Not editable via master entries until wired.",
        "readOnly": true,
        "value": "49 / 99 / 199 / 399",
    }));
    Ok(Json(json!({ "items": items })))
}

async fn get_operational_settings(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    require_ops_access(&user)?;
    let mut items = Vec::new();
    for def in OPERATIONAL_SETTINGS {
        let row = load_config_row(&state, def.key).await?;
        items.push(setting_json(*def, row));
    }
    Ok(Json(json!({ "items": items })))
}

#[derive(Deserialize)]
struct PatchSettingBody {
    value: String,
    #[serde(default)]
    isActive: Option<bool>,
}

async fn patch_pricing_setting(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SettingKeyQuery>,
    Json(body): Json<PatchSettingBody>,
) -> AppResult<Json<Value>> {
    patch_setting(&state, &user, &q.key, &body, PRICING_SETTINGS, "pricing_policies").await
}

async fn patch_operational_setting(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SettingKeyQuery>,
    Json(body): Json<PatchSettingBody>,
) -> AppResult<Json<Value>> {
    patch_setting(&state, &user, &q.key, &body, OPERATIONAL_SETTINGS, "operational_settings").await
}

#[derive(Deserialize)]
struct SettingKeyQuery {
    key: String,
}

async fn patch_setting(
    state: &AppState,
    user: &AuthUser,
    key: &str,
    body: &PatchSettingBody,
    defs: &[SettingDef],
    section: &'static str,
) -> AppResult<Json<Value>> {
    if section == "pricing_policies" {
        require_pricing_access(user)?;
    } else {
        require_ops_access(user)?;
    }
    let def = defs
        .iter()
        .find(|d| d.key == key)
        .ok_or_else(|| AppError::BadRequest("Unknown or read-only setting key".into()))?;
    let trimmed = body.value.trim();
    if trimmed.is_empty() {
        return Err(AppError::BadRequest("Value is required".into()));
    }
    let parsed: i64 = trimmed
        .parse()
        .map_err(|_| AppError::BadRequest("Value must be a whole number".into()))?;
    if parsed < def.min || parsed > def.max {
        return Err(AppError::BadRequest(format!(
            "Value must be between {} and {}",
            def.min, def.max
        )));
    }
    let before_row = load_config_row(state, key).await?;
    let before = before_row.as_ref().map(|(_, l, v, a)| json!({"label": l, "value": v, "isActive": a}));
    let mut tx = state.db.begin().await?;
    let active = body.isActive.unwrap_or(true);
    if let Some((id, _, old_v, old_a)) = before_row {
        sqlx::query(
            r#"UPDATE master_entries SET value = $1, "isActive" = $2, category = COALESCE(category, $3), "updatedAt" = NOW() WHERE id = $4"#,
        )
        .bind(trimmed)
        .bind(active)
        .bind(def.description)
        .bind(id)
        .execute(&mut *tx)
        .await?;
        master_audit::commit_with_audit(
            tx,
            AuditEvent {
                section,
                entity_type: "configuration",
                entity_id: key.to_string(),
                action: "update",
                actor_user_id: user.user_id.clone(),
                before: before.clone(),
                after: Some(json!({"value": trimmed, "isActive": active})),
            },
            Domain::ServiceMaster,
        )
        .await?;
    } else {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"INSERT INTO master_entries (id, type, label, value, category, "isActive")
               VALUES ($1, 'CONFIGURATION', $2, $3, $4, $5)"#,
        )
        .bind(id)
        .bind(key)
        .bind(trimmed)
        .bind(def.description)
        .bind(active)
        .execute(&mut *tx)
        .await?;
        master_audit::commit_with_audit(
            tx,
            AuditEvent {
                section,
                entity_type: "configuration",
                entity_id: key.to_string(),
                action: "create",
                actor_user_id: user.user_id.clone(),
                before: None,
                after: Some(json!({"value": trimmed, "isActive": active})),
            },
            Domain::ServiceMaster,
        )
        .await?;
    }
    Ok(Json(json!({"key": key, "value": trimmed, "isActive": active})))
}

fn require_pricing_access(user: &AuthUser) -> AppResult<()> {
    require_admin(user)?;
    if user.staff_role.as_deref() == Some("SUPER_ADMIN")
        || user.pages.iter().any(|p| p == "pricing-policies" || p == "master-entries")
    {
        Ok(())
    } else {
        Err(AppError::Forbidden("Missing page access: pricing-policies".into()))
    }
}

fn require_ops_access(user: &AuthUser) -> AppResult<()> {
    require_admin(user)?;
    if user.staff_role.as_deref() == Some("SUPER_ADMIN")
        || user.pages.iter().any(|p| p == "operational-settings" || p == "master-entries")
    {
        Ok(())
    } else {
        Err(AppError::Forbidden("Missing page access: operational-settings".into()))
    }
}

async fn rental_catalogue_meta(user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    Ok(Json(json!({
        "categories": ["TOOLS","DRILL","CAMERA","FURNITURE","VEHICLE","ELECTRONICS","PARTY","SPORTS","OTHER"],
        "conditions": ["NEW","GOOD","USED"],
        "cancellationPolicies": ["FLEXIBLE","MODERATE","STRICT","NON_REFUNDABLE"],
        "billingUnits": ["hourly","daily"],
        "note": "Rental listings validate against these enums in Rust. Item inventory stays on Rentals operational screens.",
    })))
}

async fn event_catalogue_meta(user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "master-entries")?;
    Ok(Json(json!({
        "vendorServices": crate::events::SERVICES,
        "note": "Event plans accept eventType as free text; vendor quote services must be from vendorServices. Packages and bookings are operational, not master rows.",
    })))
}
