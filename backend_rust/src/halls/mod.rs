//! Hall owner APIs: venue, halls, packages, calendar, operators, media.
pub mod audit;
pub mod availability;
mod policy;

use axum::{
    extract::{Path, Query, State},
    routing::{delete, get, post, put},
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

use self::audit::{bump_hall_caches, write_audit};
use self::availability::{
    acquire_hall_scope_locks, availability_check, Interval,
};
use self::policy::{enforce_booking_window, validate_deduction_basis, validate_policy_rules};

pub fn public_routes() -> Router<AppState> {
    Router::new().route("/discover", get(discover_halls))
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/{business_id}/venue", get(get_venue).patch(patch_venue))
        .route("/{business_id}/halls", get(list_halls).post(create_hall))
        .route(
            "/{business_id}/halls/{hall_id}",
            get(get_hall).patch(patch_hall).delete(archive_hall),
        )
        .route(
            "/{business_id}/halls/{hall_id}/package",
            put(put_package).get(get_package),
        )
        .route(
            "/{business_id}/halls/{hall_id}/calendar",
            get(get_calendar),
        )
        .route(
            "/{business_id}/halls/{hall_id}/blocks",
            post(create_block),
        )
        .route(
            "/{business_id}/blocks/{block_id}/release",
            post(release_block),
        )
        .route(
            "/{business_id}/blocks",
            post(create_venue_block),
        )
        .route(
            "/{business_id}/halls/{hall_id}/operators",
            get(list_operators).post(add_operator),
        )
        .route(
            "/{business_id}/halls/{hall_id}/operators/{user_id}",
            delete(remove_operator),
        )
        .route(
            "/{business_id}/halls/{hall_id}/media",
            get(list_media).post(add_media),
        )
        .route(
            "/{business_id}/halls/{hall_id}/media/{media_id}",
            delete(remove_media),
        )
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Perm {
    Owner,
    HallCalendar,
    HallPhotos,
    HallRead,
}

async fn require_hall_business(
    db: &sqlx::PgPool,
    business_id: Uuid,
    user_id: Uuid,
) -> AppResult<(Uuid, bool)> {
    let row = sqlx::query(
        r#"SELECT "ownerId", "serviceType"::text AS st, type::text AS t
           FROM businesses WHERE id = $1"#,
    )
    .bind(business_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    if row.get::<String, _>("t") != "SERVICE" || row.get::<Option<String>, _>("st").as_deref() != Some("HALL")
    {
        return Err(AppError::BadRequest(
            "Hall APIs require a SERVICE business with serviceType HALL".into(),
        ));
    }
    let owner: Uuid = row.get("ownerId");
    Ok((owner, owner == user_id))
}

async fn require_perm(
    db: &sqlx::PgPool,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    user_id: Uuid,
    perm: Perm,
) -> AppResult<()> {
    let (owner, is_owner) = require_hall_business(db, business_id, user_id).await?;
    if is_owner {
        return Ok(());
    }
    match perm {
        Perm::Owner => Err(AppError::Forbidden(
            "Only the business owner may perform this action".into(),
        )),
        Perm::HallCalendar | Perm::HallPhotos | Perm::HallRead => {
            let Some(hid) = hall_id else {
                return Err(AppError::Forbidden(
                    "Hall operator access requires a hall".into(),
                ));
            };
            let ok: bool = sqlx::query_scalar(
                r#"SELECT EXISTS(
                    SELECT 1 FROM business_hall_operators o
                    JOIN business_halls h ON h.id = o."hallId"
                    WHERE o."hallId" = $1 AND o."userId" = $2
                      AND h."businessId" = $3 AND h."archivedAt" IS NULL
                )"#,
            )
            .bind(hid)
            .bind(user_id)
            .bind(business_id)
            .fetch_one(db)
            .await?;
            if !ok {
                return Err(AppError::Forbidden(
                    "You are not an operator for this hall".into(),
                ));
            }
            let _ = owner;
            Ok(())
        }
    }
}

async fn get_venue(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, None, uid, Perm::Owner).await?;
    sqlx::query(
        r#"INSERT INTO business_hall_venue ("businessId") VALUES ($1)
           ON CONFLICT ("businessId") DO NOTHING"#,
    )
    .bind(business_id)
    .execute(&state.db)
    .await?;
    let row = sqlx::query(
        r#"SELECT to_jsonb(v) AS data FROM business_hall_venue v WHERE v."businessId" = $1"#,
    )
    .bind(business_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row.get("data")))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct VenuePatch {
    planned_hall_count: Option<i32>,
    common_parking: Option<Value>,
    hall_setup_complete: Option<bool>,
    timezone: Option<String>,
    assign_hold_hours: Option<i32>,
}

async fn patch_venue(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
    Json(body): Json<VenuePatch>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, None, uid, Perm::Owner).await?;
    if let Some(c) = body.planned_hall_count {
        if !(1..=50).contains(&c) {
            return Err(AppError::BadRequest(
                "plannedHallCount must be between 1 and 50".into(),
            ));
        }
    }
    if let Some(ref parking) = body.common_parking {
        validate_parking(parking)?;
    }
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut tx, business_id, Some(&[])).await?;
    sqlx::query(
        r#"INSERT INTO business_hall_venue ("businessId") VALUES ($1)
           ON CONFLICT ("businessId") DO NOTHING"#,
    )
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"UPDATE business_hall_venue SET
           "plannedHallCount" = COALESCE($2, "plannedHallCount"),
           "commonParking" = COALESCE($3, "commonParking"),
           "hallSetupComplete" = COALESCE($4, "hallSetupComplete"),
           timezone = COALESCE($5, timezone),
           "assignHoldHours" = COALESCE($6, "assignHoldHours"),
           "updatedAt" = NOW()
           WHERE "businessId" = $1"#,
    )
    .bind(business_id)
    .bind(body.planned_hall_count)
    .bind(body.common_parking)
    .bind(body.hall_setup_complete)
    .bind(body.timezone.as_deref())
    .bind(body.assign_hold_hours)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut tx,
        business_id,
        None,
        "venue",
        &business_id.to_string(),
        "patch",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, None).await?;
    tx.commit().await?;
    get_venue(State(state), user, Path(business_id)).await
}

async fn list_halls(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let (owner, is_owner) = require_hall_business(&state.db, business_id, uid).await?;
    let rows = if is_owner || owner == uid {
        sqlx::query(
            r#"SELECT to_jsonb(h) AS data FROM business_halls h
               WHERE h."businessId" = $1 AND h."archivedAt" IS NULL
               ORDER BY h."hallNumber""#,
        )
        .bind(business_id)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            r#"SELECT to_jsonb(h) AS data FROM business_halls h
               JOIN business_hall_operators o ON o."hallId" = h.id
               WHERE h."businessId" = $1 AND h."archivedAt" IS NULL AND o."userId" = $2
               ORDER BY h."hallNumber""#,
        )
        .bind(business_id)
        .bind(uid)
        .fetch_all(&state.db)
        .await?
    };
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateHall {
    name: String,
    #[serde(default = "default_indoor")]
    space_type: String,
    #[serde(default = "default_true")]
    use_hall_name: bool,
}
fn default_indoor() -> String {
    "indoor".into()
}
fn default_true() -> bool {
    true
}

async fn create_hall(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
    Json(body): Json<CreateHall>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, None, uid, Perm::Owner).await?;
    let name = body.name.trim();
    if name.is_empty() || name.len() > 200 {
        return Err(AppError::BadRequest("Hall name is required".into()));
    }
    if !["indoor", "outdoor"].contains(&body.space_type.as_str()) {
        return Err(AppError::BadRequest("spaceType must be indoor or outdoor".into()));
    }
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, None).await?;
    sqlx::query(
        r#"INSERT INTO business_hall_venue ("businessId") VALUES ($1)
           ON CONFLICT ("businessId") DO NOTHING"#,
    )
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    let venue = sqlx::query(
        r#"SELECT "plannedHallCount" FROM business_hall_venue WHERE "businessId" = $1"#,
    )
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;
    let planned: i32 = venue.get("plannedHallCount");
    let count: i64 = sqlx::query_scalar(
        r#"SELECT count(*) FROM business_halls
           WHERE "businessId" = $1 AND "archivedAt" IS NULL"#,
    )
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;
    if count >= planned as i64 {
        return Err(AppError::Conflict(format!(
            "All {planned} halls are added. Increase plannedHallCount (edit parking/setup) to add more"
        )));
    }
    let next_num: i32 = sqlx::query_scalar(
        r#"SELECT COALESCE(MAX("hallNumber"), 0) + 1 FROM business_halls WHERE "businessId" = $1"#,
    )
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO business_halls
           (id, "businessId", "hallNumber", "useHallName", name, "spaceType")
           VALUES ($1,$2,$3,$4,$5,$6)"#,
    )
    .bind(id)
    .bind(business_id)
    .bind(next_num)
    .bind(body.use_hall_name)
    .bind(name)
    .bind(&body.space_type)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(id),
        "hall",
        &id.to_string(),
        "create",
        uid,
        json!({"name": name}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(id)).await?;
    crate::outbox::notify(
        &mut tx,
        business_id,
        uid,
        "Hall added",
        &format!("Hall \"{name}\" was added to your venue."),
        json!({"type": "hall_update", "businessId": business_id, "hallId": id}),
    )
    .await?;
    tx.commit().await?;
    get_hall(State(state), user, Path((business_id, id))).await
}

async fn get_hall(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallRead).await?;
    let row = sqlx::query(
        r#"SELECT to_jsonb(h) || jsonb_build_object(
             'venueTimezone', (SELECT timezone FROM business_hall_venue WHERE "businessId" = h."businessId"),
             'package', (SELECT package FROM business_hall_package_revisions WHERE id = h."packageRevisionId")
           ) AS data
           FROM business_halls h
           WHERE h.id = $1 AND h."businessId" = $2 AND h."archivedAt" IS NULL"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall not found".into()))?;
    Ok(Json(row.get("data")))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct HallPatch {
    name: Option<String>,
    space_type: Option<String>,
    listing_active: Option<bool>,
    use_hall_name: Option<bool>,
    cover_image_url: Option<String>,
}

async fn patch_hall(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<HallPatch>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    if let Some(ref st) = body.space_type {
        if !["indoor", "outdoor"].contains(&st.as_str()) {
            return Err(AppError::BadRequest("spaceType must be indoor or outdoor".into()));
        }
    }
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    sqlx::query(
        r#"UPDATE business_halls SET
           name = COALESCE($3, name),
           "spaceType" = COALESCE($4, "spaceType"),
           "listingActive" = COALESCE($5, "listingActive"),
           "useHallName" = COALESCE($6, "useHallName"),
           "coverImageUrl" = COALESCE($7, "coverImageUrl"),
           "updatedAt" = NOW()
           WHERE id = $1 AND "businessId" = $2 AND "archivedAt" IS NULL"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .bind(body.name.as_deref().map(str::trim))
    .bind(body.space_type.as_deref())
    .bind(body.listing_active)
    .bind(body.use_hall_name)
    .bind(body.cover_image_url.as_deref())
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "hall",
        &hall_id.to_string(),
        "patch",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    tx.commit().await?;
    get_hall(State(state), user, Path((business_id, hall_id))).await
}

async fn archive_hall(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    let active: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM hall_reservations
            WHERE "hallId" = $1 AND status IN ('HELD','CONFIRMED')
              AND (status = 'CONFIRMED' OR "expiresAt" > NOW())
        )"#,
    )
    .bind(hall_id)
    .fetch_one(&mut *tx)
    .await?;
    if active {
        return Err(AppError::Conflict(
            "Cancel or release active reservations before archiving this hall".into(),
        ));
    }
    sqlx::query(
        r#"UPDATE business_halls SET "archivedAt" = NOW(), "listingActive" = false, "updatedAt" = NOW()
           WHERE id = $1 AND "businessId" = $2 AND "archivedAt" IS NULL"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "hall",
        &hall_id.to_string(),
        "archive",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    crate::outbox::notify(
        &mut tx,
        business_id,
        uid,
        "Hall archived",
        "A hall was archived and removed from the active list.",
        json!({"type": "hall_update", "businessId": business_id, "hallId": hall_id}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"archived": true, "hallId": hall_id})))
}

async fn get_package(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallRead).await?;
    let row = sqlx::query(
        r#"SELECT r.revision, r.package, r."createdAt", h."packageSaved"
           FROM business_halls h
           LEFT JOIN business_hall_package_revisions r ON r.id = h."packageRevisionId"
           WHERE h.id = $1 AND h."businessId" = $2"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall not found".into()))?;
    Ok(Json(json!({
        "packageSaved": row.get::<bool,_>("packageSaved"),
        "revision": row.try_get::<Option<i32>,_>("revision").ok().flatten(),
        "package": row.try_get::<Option<Value>,_>("package").ok().flatten(),
        "createdAt": row.try_get::<Option<DateTime<Utc>>,_>("createdAt").ok().flatten(),
    })))
}

async fn put_package(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    let pkg = body
        .get("package")
        .cloned()
        .or_else(|| Some(body.clone()))
        .unwrap();
    validate_package(&pkg)?;
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    let exists: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM business_halls WHERE id=$1 AND "businessId"=$2 AND "archivedAt" IS NULL)"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;
    if !exists {
        return Err(AppError::NotFound("Hall not found".into()));
    }
    let next_rev: i32 = sqlx::query_scalar(
        r#"SELECT COALESCE(MAX(revision), 0) + 1 FROM business_hall_package_revisions WHERE "hallId" = $1"#,
    )
    .bind(hall_id)
    .fetch_one(&mut *tx)
    .await?;
    let rev_id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO business_hall_package_revisions
           (id, "hallId", revision, package, "createdBy")
           VALUES ($1,$2,$3,$4,$5)"#,
    )
    .bind(rev_id)
    .bind(hall_id)
    .bind(next_rev)
    .bind(&pkg)
    .bind(uid)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        r#"UPDATE business_halls SET
           "packageRevisionId" = $3, "packageSaved" = true, "updatedAt" = NOW()
           WHERE id = $1 AND "businessId" = $2"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .bind(rev_id)
    .execute(&mut *tx)
    .await?;
    // Do NOT delete calendar blocks when slots are disabled.
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "package",
        &rev_id.to_string(),
        "save",
        uid,
        json!({"revision": next_rev}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    crate::outbox::notify(
        &mut tx,
        business_id,
        uid,
        "Package saved",
        "Hall price and package settings were updated.",
        json!({"type": "hall_package", "businessId": business_id, "hallId": hall_id, "revision": next_rev}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({
        "packageSaved": true,
        "revision": next_rev,
        "packageRevisionId": rev_id,
        "package": pkg,
    })))
}

fn optional_whole_number(value: Option<&Value>, field: &str, min: i64, max: i64) -> AppResult<()> {
    match value {
        None | Some(Value::Null) => Ok(()),
        Some(_) => {
            whole_number(value, field, min, max)?;
            Ok(())
        }
    }
}

fn whole_number(value: Option<&Value>, field: &str, min: i64, max: i64) -> AppResult<i64> {
    let n = value.and_then(|v| v.as_i64()).ok_or_else(|| {
        AppError::BadRequest(format!("{field} must be a whole number"))
    })?;
    if !(min..=max).contains(&n) {
        return Err(AppError::BadRequest(format!(
            "{field} must be between {min} and {max}"
        )));
    }
    Ok(n)
}

fn validate_clock(value: Option<&Value>, field: &str) -> AppResult<u32> {
    let text = value
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest(format!("{field} must be HH:MM")))?;
    let Some((h, m)) = text.split_once(':') else {
        return Err(AppError::BadRequest(format!("{field} must be HH:MM")));
    };
    if h.len() != 2 || m.len() != 2 {
        return Err(AppError::BadRequest(format!("{field} must be HH:MM")));
    }
    let hour: u32 = h
        .parse()
        .map_err(|_| AppError::BadRequest(format!("{field} must be HH:MM")))?;
    let minute: u32 = m
        .parse()
        .map_err(|_| AppError::BadRequest(format!("{field} must be HH:MM")))?;
    if hour > 23 || minute > 59 {
        return Err(AppError::BadRequest(format!("{field} must be HH:MM")));
    }
    Ok(hour * 60 + minute)
}

fn validate_parking(value: &Value) -> AppResult<()> {
    let obj = value.as_object().ok_or_else(|| {
        AppError::BadRequest("commonParking must be an object with car and bike counts".into())
    })?;
    for key in ["car", "bike"] {
        whole_number(obj.get(key), &format!("commonParking.{key}"), 0, 10_000)?;
    }
    Ok(())
}

fn validate_package(pkg: &Value) -> AppResult<()> {
    let events = pkg
        .get("events")
        .and_then(|v| v.as_array())
        .ok_or_else(|| AppError::BadRequest("package.events is required".into()))?;
    if events.is_empty() {
        return Err(AppError::BadRequest(
            "Select at least one event type".into(),
        ));
    }
    let facilities = pkg
        .get("facilities")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|v| v.as_str().map(str::to_owned))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let has_ac = facilities.iter().any(|f| f == "AC");
    let capacity = pkg.get("capacity").ok_or_else(|| {
        AppError::BadRequest("package.capacity.seat and package.capacity.dine are required".into())
    })?;
    whole_number(capacity.get("seat"), "capacity.seat", 0, 100_000)?;
    whole_number(capacity.get("dine"), "capacity.dine", 0, 100_000)?;
    let offers = pkg
        .get("slotOffers")
        .and_then(|v| v.as_array())
        .ok_or_else(|| AppError::BadRequest("package.slotOffers is required".into()))?;
    let enabled: Vec<_> = offers
        .iter()
        .filter(|o| o.get("enabled").and_then(|v| v.as_bool()).unwrap_or(true))
        .collect();
    if enabled.is_empty() {
        return Err(AppError::BadRequest(
            "Enable at least one time slot with pricing".into(),
        ));
    }
    for (i, offer) in enabled.iter().enumerate() {
        let from = validate_clock(offer.get("hallFrom"), &format!("slotOffers[{i}].hallFrom"))?;
        let to = validate_clock(offer.get("hallTo"), &format!("slotOffers[{i}].hallTo"))?;
        if to <= from {
            return Err(AppError::BadRequest(format!(
                "slotOffers[{i}] end time must be after its start time"
            )));
        }
        let offer_ac = offer.get("offerAc").and_then(|v| v.as_bool()).unwrap_or(false);
        if offer_ac && !has_ac {
            return Err(AppError::BadRequest(
                "AC pricing requires the AC facility".into(),
            ));
        }
        if offer.get("offerNoAc").and_then(|v| v.as_bool()).unwrap_or(true) {
            whole_number(
                offer.get("priceNoAc"),
                &format!("slotOffers[{i}].priceNoAc"),
                0,
                100_000_000,
            )?;
        }
        if offer_ac {
            whole_number(
                offer.get("priceAc"),
                &format!("slotOffers[{i}].priceAc"),
                0,
                100_000_000,
            )?;
        }
    }
    let payment = pkg.get("payment").ok_or_else(|| {
        AppError::BadRequest("package.payment is required".into())
    })?;
    match payment.get("advanceType").and_then(|v| v.as_str()).unwrap_or("fixed") {
        "fixed" => {
            whole_number(payment.get("advanceFixed"), "payment.advanceFixed", 0, 100_000_000)?;
            optional_whole_number(payment.get("advancePct"), "payment.advancePct", 0, 100)?;
        }
        "percent" => {
            whole_number(payment.get("advancePct"), "payment.advancePct", 0, 100)?;
            optional_whole_number(
                payment.get("advanceFixed"),
                "payment.advanceFixed",
                0,
                100_000_000,
            )?;
        }
        other => {
            return Err(AppError::BadRequest(format!(
                "payment.advanceType must be fixed or percent (got {other})"
            )));
        }
    }
    whole_number(payment.get("fullDueDays"), "payment.fullDueDays", 0, 3650)?;
    whole_number(pkg.get("bookWindowMonths"), "bookWindowMonths", 1, 36)?;
    whole_number(pkg.get("minNoticeDays"), "minNoticeDays", 0, 365)?;
    validate_policy_rules(
        pkg.get("cancelRules")
            .unwrap_or(&Value::Array(vec![])),
        "cancelRules",
    )?;
    validate_policy_rules(
        pkg.get("rescheduleRules")
            .unwrap_or(&Value::Array(vec![])),
        "rescheduleRules",
    )?;
    validate_deduction_basis(pkg.get("deductionBasis"))?;
    Ok(())
}

pub(crate) async fn load_hall_package(
    tx: &mut sqlx::PgConnection,
    hall_id: Uuid,
) -> AppResult<Option<Value>> {
    let row = sqlx::query(
        r#"SELECT rev.package AS package
           FROM business_halls h
           LEFT JOIN business_hall_package_revisions rev ON rev.id = h."packageRevisionId"
           WHERE h.id = $1"#,
    )
    .bind(hall_id)
    .fetch_optional(&mut *tx)
    .await?;
    match row {
        None => Ok(None),
        Some(r) => Ok(r.try_get("package")?),
    }
}

pub(crate) fn ensure_package_window(pkg: Option<&Value>, start: DateTime<Utc>) -> AppResult<()> {
    if let Some(pkg) = pkg {
        enforce_booking_window(pkg, start, Utc::now())?;
    }
    Ok(())
}

#[derive(Deserialize)]
struct CalQuery {
    from: String,
    to: String,
}

async fn get_calendar(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Query(q): Query<CalQuery>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallCalendar).await?;
    let from = parse_ts(&q.from)?;
    let to = parse_ts(&q.to)?;
    if to <= from {
        return Err(AppError::BadRequest("to must be after from".into()));
    }
    let tz: String = sqlx::query_scalar(
        r#"SELECT timezone FROM business_hall_venue WHERE "businessId" = $1"#,
    )
    .bind(business_id)
    .fetch_optional(&state.db)
    .await?
    .unwrap_or_else(|| "Asia/Kolkata".into());

    let blocks = sqlx::query(
        r#"SELECT to_jsonb(b) AS data FROM hall_calendar_blocks b
           WHERE b."businessId" = $1
             AND (b."hallId" = $2 OR b."hallId" IS NULL)
             AND b."startAt" < $4 AND b."endAt" > $3
           ORDER BY b."startAt""#,
    )
    .bind(business_id)
    .bind(hall_id)
    .bind(from)
    .bind(to)
    .fetch_all(&state.db)
    .await?;

    let reservations = sqlx::query(
        r#"SELECT to_jsonb(r) AS data FROM hall_reservations r
           WHERE r."hallId" = $1
             AND r.status IN ('HELD','CONFIRMED')
             AND (r.status = 'CONFIRMED' OR r."expiresAt" > NOW())
             AND r."startAt" < $3 AND r."endAt" > $2
           ORDER BY r."startAt""#,
    )
    .bind(hall_id)
    .bind(from)
    .bind(to)
    .fetch_all(&state.db)
    .await?;

    let hall = sqlx::query(
        r#"SELECT "packageSaved",
           (SELECT package FROM business_hall_package_revisions WHERE id = h."packageRevisionId") AS package
           FROM business_halls h WHERE h.id = $1"#,
    )
    .bind(hall_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall not found".into()))?;

    Ok(Json(json!({
        "venueTimezone": tz,
        "timezoneLabel": "Times shown in IST (Kolkata)",
        "packageSaved": hall.get::<bool,_>("packageSaved"),
        "package": hall.try_get::<Option<Value>,_>("package").ok().flatten(),
        "blocks": blocks.iter().map(|r| r.get::<Value,_>("data")).collect::<Vec<_>>(),
        "reservations": reservations.iter().map(|r| r.get::<Value,_>("data")).collect::<Vec<_>>(),
        "from": from,
        "to": to,
    })))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BlockBody {
    start_at: String,
    end_at: String,
    #[serde(default = "default_offline")]
    reason: String,
    #[serde(default)]
    notes: String,
}
fn default_offline() -> String {
    "offline".into()
}

async fn create_block(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<BlockBody>,
) -> AppResult<Json<Value>> {
    create_block_inner(state, user, business_id, Some(hall_id), body).await
}

async fn create_venue_block(
    State(state): State<AppState>,
    user: AuthUser,
    Path(business_id): Path<Uuid>,
    Json(body): Json<BlockBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, None, uid, Perm::Owner).await?;
    create_block_inner(state, user, business_id, None, body).await
}

async fn create_block_inner(
    state: AppState,
    user: AuthUser,
    business_id: Uuid,
    hall_id: Option<Uuid>,
    body: BlockBody,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    if let Some(hid) = hall_id {
        require_perm(&state.db, business_id, Some(hid), uid, Perm::HallCalendar).await?;
    }
    if !["offline", "temp", "maintenance", "other"].contains(&body.reason.as_str()) {
        return Err(AppError::BadRequest("Invalid block reason".into()));
    }
    let interval = Interval::new(parse_ts(&body.start_at)?, parse_ts(&body.end_at)?)?;
    let mut tx = state.db.begin().await?;
    let lock_ids = match hall_id {
        Some(h) => Some(vec![h]),
        None => None,
    };
    acquire_hall_scope_locks(
        &mut *tx,
        business_id,
        lock_ids.as_deref(),
    )
    .await?;
    availability_check(&mut *tx, business_id, hall_id, interval, None).await?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO hall_calendar_blocks
           (id, "businessId", "hallId", "startAt", "endAt", reason, notes, "createdBy")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8)"#,
    )
    .bind(id)
    .bind(business_id)
    .bind(hall_id)
    .bind(interval.start)
    .bind(interval.end)
    .bind(&body.reason)
    .bind(body.notes.trim())
    .bind(uid)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        hall_id,
        "block",
        &id.to_string(),
        "create",
        uid,
        json!({"reason": body.reason}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, hall_id).await?;
    crate::outbox::notify(
        &mut tx,
        business_id,
        uid,
        "Calendar updated",
        "A calendar block was added.",
        json!({"type": "hall_calendar_update", "businessId": business_id, "hallId": hall_id, "blockId": id}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"id": id, "releasedAt": null})))
}

async fn release_block(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, block_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let block = sqlx::query(
        r#"SELECT "hallId", "releasedAt" FROM hall_calendar_blocks
           WHERE id = $1 AND "businessId" = $2"#,
    )
    .bind(block_id)
    .bind(business_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Block not found".into()))?;
    if block.get::<Option<DateTime<Utc>>, _>("releasedAt").is_some() {
        return Err(AppError::Conflict("Block already released".into()));
    }
    let hall_id: Option<Uuid> = block.get("hallId");
    if let Some(hid) = hall_id {
        require_perm(&state.db, business_id, Some(hid), uid, Perm::HallCalendar).await?;
    } else {
        require_perm(&state.db, business_id, None, uid, Perm::Owner).await?;
    }
    let mut tx = state.db.begin().await?;
    let lock = hall_id.map(|h| vec![h]);
    acquire_hall_scope_locks(&mut *tx, business_id, lock.as_deref()).await?;
    sqlx::query(
        r#"UPDATE hall_calendar_blocks
           SET "releasedAt" = NOW(), "releasedBy" = $2
           WHERE id = $1 AND "releasedAt" IS NULL"#,
    )
    .bind(block_id)
    .bind(uid)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        hall_id,
        "block",
        &block_id.to_string(),
        "release",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, hall_id).await?;
    crate::outbox::notify(
        &mut tx,
        business_id,
        uid,
        "Calendar updated",
        "A calendar block was released.",
        json!({"type": "hall_calendar_update", "businessId": business_id, "blockId": block_id}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(json!({"id": block_id, "released": true})))
}

async fn list_operators(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    let rows = sqlx::query(
        r#"SELECT jsonb_build_object(
             'userId', o."userId", 'name', u.name, 'phoneNumber', u."phoneNumber"
           ) AS data
           FROM business_hall_operators o
           JOIN users u ON u.id = o."userId"
           JOIN business_halls h ON h.id = o."hallId"
           WHERE o."hallId" = $1 AND h."businessId" = $2"#,
    )
    .bind(hall_id)
    .bind(business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpBody {
    user_id: Uuid,
}

async fn add_operator(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<OpBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    let mut tx = state.db.begin().await?;
    // Business, then venue, then this hall, before the operator row and its audit foreign keys.
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    sqlx::query(
        r#"INSERT INTO business_hall_operators ("hallId", "userId")
           SELECT $1, $2 FROM business_halls
           WHERE id = $1 AND "businessId" = $3 AND "archivedAt" IS NULL
           ON CONFLICT DO NOTHING"#,
    )
    .bind(hall_id)
    .bind(body.user_id)
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "operator",
        &body.user_id.to_string(),
        "add",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    tx.commit().await?;
    Ok(Json(json!({"ok": true})))
}

async fn remove_operator(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id, user_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::Owner).await?;
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    sqlx::query(
        r#"DELETE FROM business_hall_operators o
           USING business_halls h
           WHERE o."hallId" = h.id AND o."hallId" = $1 AND o."userId" = $2
             AND h."businessId" = $3"#,
    )
    .bind(hall_id)
    .bind(user_id)
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "operator",
        &user_id.to_string(),
        "remove",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    tx.commit().await?;
    Ok(Json(json!({"ok": true})))
}

async fn list_media(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallPhotos).await?;
    let rows = sqlx::query(
        r#"SELECT to_jsonb(m) AS data FROM business_hall_media m
           JOIN business_halls h ON h.id = m."hallId"
           WHERE m."hallId" = $1 AND h."businessId" = $2
           ORDER BY m."sortOrder", m."createdAt""#,
    )
    .bind(hall_id)
    .bind(business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MediaBody {
    url: String,
    #[serde(default)]
    sort_order: i32,
}

async fn add_media(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<MediaBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallPhotos).await?;
    let url = body.url.trim();
    if url.is_empty() || url.len() > 2000 {
        return Err(AppError::BadRequest("Media URL is required".into()));
    }
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    let id = Uuid::new_v4();
    sqlx::query(
        r#"INSERT INTO business_hall_media (id, "hallId", url, "sortOrder")
           SELECT $1, $2, $3, $4 FROM business_halls
           WHERE id = $2 AND "businessId" = $5 AND "archivedAt" IS NULL"#,
    )
    .bind(id)
    .bind(hall_id)
    .bind(url)
    .bind(body.sort_order)
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "media",
        &id.to_string(),
        "add",
        uid,
        json!({"url": url}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    tx.commit().await?;
    Ok(Json(json!({"id": id, "url": url})))
}

async fn remove_media(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business_id, hall_id, media_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    require_perm(&state.db, business_id, Some(hall_id), uid, Perm::HallPhotos).await?;
    let mut tx = state.db.begin().await?;
    acquire_hall_scope_locks(&mut *tx, business_id, Some(&[hall_id])).await?;
    sqlx::query(
        r#"DELETE FROM business_hall_media m
           USING business_halls h
           WHERE m.id = $1 AND m."hallId" = $2 AND h.id = m."hallId" AND h."businessId" = $3"#,
    )
    .bind(media_id)
    .bind(hall_id)
    .bind(business_id)
    .execute(&mut *tx)
    .await?;
    write_audit(
        &mut *tx,
        business_id,
        Some(hall_id),
        "media",
        &media_id.to_string(),
        "remove",
        uid,
        json!({}),
    )
    .await?;
    bump_hall_caches(&mut tx, business_id, Some(hall_id)).await?;
    tx.commit().await?;
    Ok(Json(json!({"ok": true})))
}

fn parse_ts(value: &str) -> AppResult<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value)
        .map(|d| d.with_timezone(&Utc))
        .map_err(|_| AppError::BadRequest("Timestamps must be RFC3339 with timezone".into()))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiscoverQuery {
    city_id: Option<Uuid>,
}

/// Customer discovery: active halls with a saved package on verified HALL businesses.
async fn discover_halls(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(q): Query<DiscoverQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(
        r#"SELECT jsonb_build_object(
             'hallId', h.id,
             'hallName', h.name,
             'spaceType', h."spaceType",
             'coverImageUrl', h."coverImageUrl",
             'businessId', b.id,
             'businessName', b.name,
             'location', b.location,
             'cityId', b."cityId",
             'venueTimezone', COALESCE(v.timezone, 'Asia/Kolkata'),
             'timezoneLabel', 'Times shown in IST (Kolkata)'
           ) AS data
           FROM business_halls h
           JOIN businesses b ON b.id = h."businessId"
           LEFT JOIN business_hall_venue v ON v."businessId" = b.id
           WHERE b.type = 'SERVICE' AND b."serviceType"::text = 'HALL'
             AND b.status = 'VERIFIED'
             AND h."archivedAt" IS NULL
             AND h."listingActive" = true
             AND h."packageSaved" = true
             AND ($1::uuid IS NULL OR b."cityId" = $1)
           ORDER BY b.name, h."hallNumber"
           LIMIT 100"#,
    )
    .bind(q.city_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| r.get("data")).collect()))
}
