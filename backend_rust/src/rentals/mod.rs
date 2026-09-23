use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;
use chrono::NaiveDate;

use crate::common::pg::{RENTAL_ITEM_COLS, RENTAL_RESERVATION_COLS};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

mod listing;
mod policy;
mod fulfillment;
mod booking;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_items).post(create_item))
        .route("/stores", get(list_stores))
        .route("/my-items", get(my_items))
        .route("/reservations/my", get(my_reservations))
        .route("/reservations/owner", get(owner_reservations))
        .route("/reservations/{res_id}/ack/{action}", patch(fulfillment::acknowledge))
        .route("/reservations/{res_id}/advance-order", post(booking::advance_order))
        .route("/reservations/{res_id}/otp", post(booking::verify_otp))
        .route("/reservations/{res_id}/settle", post(booking::settle))
        .route("/reservations/{res_id}/confirm", patch(confirm_reservation))
        .route("/reservations/{res_id}/reject", patch(reject_reservation))
        .route("/reservations/{res_id}/start", patch(start_reservation))
        .route(
            "/reservations/{res_id}/complete",
            patch(complete_reservation),
        )
        .route("/reservations/{res_id}/cancel", patch(cancel_reservation))
        .route("/{id}/reserve", post(create_reservation))
        .route("/{id}", get(get_item).patch(update_item))
}

#[derive(Deserialize, Default)]
struct CatalogQuery {
    lat: Option<String>,
    lng: Option<String>,
    #[serde(rename = "cityId", default)]
    city_id: Option<String>,
    #[serde(rename = "businessId", default)]
    business_id: Option<String>,
    #[serde(rename = "radiusKm", default)]
    radius_km: Option<String>,
}

fn aliased_rental_cols() -> String {
    RENTAL_ITEM_COLS
        .split(',')
        .map(|c| format!("i.{}", c.trim()))
        .collect::<Vec<_>>()
        .join(", ")
}

async fn list_items(
    State(state): State<AppState>,
    Query(q): Query<CatalogQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let coords = match (&q.lat, &q.lng) {
        (None, None) => None,
        (Some(lat), Some(lng)) => {
            let lat = lat
                .parse::<f64>()
                .map_err(|_| AppError::BadRequest("lat must be a number".into()))?;
            let lng = lng
                .parse::<f64>()
                .map_err(|_| AppError::BadRequest("lng must be a number".into()))?;
            if !lat.is_finite()
                || !lng.is_finite()
                || !(-90.0..=90.0).contains(&lat)
                || !(-180.0..=180.0).contains(&lng)
            {
                return Err(AppError::BadRequest("lat and lng are required".into()));
            }
            Some((lat, lng))
        }
        _ => return Err(AppError::BadRequest("lat and lng are required".into())),
    };
    let city_id = match q.city_id.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        None => None,
        Some(raw) => Some(
            Uuid::parse_str(raw).map_err(|_| AppError::BadRequest("Invalid city".into()))?,
        ),
    };
    let store_id = match q.business_id.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        None => None,
        Some(raw) => Some(
            Uuid::parse_str(raw).map_err(|_| AppError::BadRequest("Invalid store".into()))?,
        ),
    };

    if let Some(store_id) = store_id {
        return list_store_items(state, store_id).await;
    }

    if coords.is_none() && city_id.is_none() {
        return Ok(Json(vec![]));
    }

    let has_gps = coords.is_some();
    let (lat, lng) = coords.unwrap_or((0.0, 0.0));
    let radius = listing::parse_radius_km(q.radius_km.as_deref());
    let (min_lat, max_lat, min_lng, max_lng) = if has_gps {
        listing::catalog_bbox(lat, lng, radius)
    } else {
        (-90.0, 90.0, -180.0, 180.0)
    };
    let cols = aliased_rental_cols();
    let rows = sqlx::query(&format!(
        r#"SELECT {cols},
            COALESCE(i."pickupLat", c.lat::float8) AS pin_lat,
            COALESCE(i."pickupLng", c.lng::float8) AS pin_lng,
            b."cityId" AS "businessCityId"
           FROM rental_items i
           LEFT JOIN businesses b ON b.id = i."businessId"
           LEFT JOIN cities c ON c.id = b."cityId"
           WHERE i."isAvailable" = true
           AND (i."businessId" IS NULL OR b.status::text = 'VERIFIED')
           AND (
             ($1::uuid IS NOT NULL AND b."cityId" = $1)
             OR (
               $2::float8 IS NOT NULL
               AND COALESCE(i."pickupLat", c.lat::float8) BETWEEN $3 AND $4
               AND COALESCE(i."pickupLng", c.lng::float8) BETWEEN $5 AND $6
             )
           )
           ORDER BY i."createdAt" DESC
           LIMIT 400"#
    ))
    .bind(city_id)
    .bind(if has_gps { Some(lat) } else { None::<f64> })
    .bind(min_lat)
    .bind(max_lat)
    .bind(min_lng)
    .bind(max_lng)
    .fetch_all(&state.db)
    .await?;

    let mut scored: Vec<(f64, Value)> = Vec::new();
    for row in &rows {
        let pin = match (
            row.try_get::<Option<f64>, _>("pin_lat").ok().flatten(),
            row.try_get::<Option<f64>, _>("pin_lng").ok().flatten(),
        ) {
            (Some(a), Some(b)) => Some((a, b)),
            _ => None,
        };
        let item_city = row.try_get::<Option<Uuid>, _>("businessCityId").ok().flatten();
        if has_gps {
            if !listing::is_nearby(lat, lng, city_id, pin, item_city, radius) {
                continue;
            }
        } else if city_id != item_city {
            continue;
        }
        let mut value = item_json(row);
        let distance = if has_gps {
            pin.map(|(plat, plng)| listing::haversine_km(lat, lng, plat, plng))
        } else {
            None
        };
        if let Some(d) = distance {
            value["distanceKm"] = json!((d * 10.0).round() / 10.0);
        }
        scored.push((distance.unwrap_or(f64::MAX), value));
    }
    scored.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    Ok(Json(scored.into_iter().take(100).map(|(_, v)| v).collect()))
}

async fn list_store_items(state: AppState, store_id: Uuid) -> AppResult<Json<Vec<Value>>> {
    let cols = aliased_rental_cols();
    let rows = sqlx::query(&format!(
        r#"SELECT {cols}
           FROM rental_items i
           JOIN businesses b ON b.id = i."businessId"
           WHERE i."businessId" = $1
             AND i."isAvailable" = true
             AND b.type = 'RENTAL'
             AND b.status::text = 'VERIFIED'
           ORDER BY i."createdAt" DESC
           LIMIT 200"#
    ))
    .bind(store_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
}

async fn list_stores(
    State(state): State<AppState>,
    Query(q): Query<CatalogQuery>,
) -> AppResult<Json<Vec<Value>>> {
    let coords = match (&q.lat, &q.lng) {
        (None, None) => None,
        (Some(lat), Some(lng)) => {
            let lat = lat
                .parse::<f64>()
                .map_err(|_| AppError::BadRequest("lat must be a number".into()))?;
            let lng = lng
                .parse::<f64>()
                .map_err(|_| AppError::BadRequest("lng must be a number".into()))?;
            if !lat.is_finite()
                || !lng.is_finite()
                || !(-90.0..=90.0).contains(&lat)
                || !(-180.0..=180.0).contains(&lng)
            {
                return Err(AppError::BadRequest("lat and lng are required".into()));
            }
            Some((lat, lng))
        }
        _ => return Err(AppError::BadRequest("lat and lng are required".into())),
    };
    let city_id = match q.city_id.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        None => None,
        Some(raw) => Some(
            Uuid::parse_str(raw).map_err(|_| AppError::BadRequest("Invalid city".into()))?,
        ),
    };
    if coords.is_none() && city_id.is_none() {
        return Ok(Json(vec![]));
    }
    let has_gps = coords.is_some();
    let (lat, lng) = coords.unwrap_or((0.0, 0.0));
    let radius = listing::parse_radius_km(q.radius_km.as_deref());
    let (min_lat, max_lat, min_lng, max_lng) = if has_gps {
        listing::catalog_bbox(lat, lng, radius)
    } else {
        (-90.0, 90.0, -180.0, 180.0)
    };
    let rows = sqlx::query(
        r#"SELECT b.id, b.name, b.location, b."cityId", b.phone, b.status::text AS status,
            COALESCE(c.lat::float8, p.lat) AS pin_lat,
            COALESCE(c.lng::float8, p.lng) AS pin_lng,
            (SELECT COUNT(*)::int FROM rental_items i
              WHERE i."businessId" = b.id AND i."isAvailable" = true) AS "itemCount"
           FROM businesses b
           LEFT JOIN cities c ON c.id = b."cityId"
           LEFT JOIN LATERAL (
             SELECT i."pickupLat" AS lat, i."pickupLng" AS lng
             FROM rental_items i
             WHERE i."businessId" = b.id
               AND i."pickupLat" IS NOT NULL
               AND i."pickupLng" IS NOT NULL
             ORDER BY i."createdAt" DESC
             LIMIT 1
           ) p ON true
           WHERE b.type = 'RENTAL' AND b.status::text = 'VERIFIED'
           AND (
             ($1::uuid IS NOT NULL AND b."cityId" = $1)
             OR (
               $2::float8 IS NOT NULL
               AND COALESCE(c.lat::float8, p.lat) BETWEEN $3 AND $4
               AND COALESCE(c.lng::float8, p.lng) BETWEEN $5 AND $6
             )
           )
           ORDER BY b."createdAt" DESC
           LIMIT 200"#
    )
    .bind(city_id)
    .bind(if has_gps { Some(lat) } else { None::<f64> })
    .bind(min_lat)
    .bind(max_lat)
    .bind(min_lng)
    .bind(max_lng)
    .fetch_all(&state.db)
    .await?;

    let mut scored: Vec<(f64, Value)> = Vec::new();
    for row in &rows {
        let pin = match (
            row.try_get::<Option<f64>, _>("pin_lat").ok().flatten(),
            row.try_get::<Option<f64>, _>("pin_lng").ok().flatten(),
        ) {
            (Some(a), Some(b)) => Some((a, b)),
            _ => None,
        };
        let item_city = row.try_get::<Option<Uuid>, _>("cityId").ok().flatten();
        if has_gps {
            if !listing::is_nearby(lat, lng, city_id, pin, item_city, radius) {
                continue;
            }
        } else if city_id != item_city {
            continue;
        }
        let mut value = json!({
            "id": row.get::<Uuid, _>("id").to_string(),
            "name": row.get::<String, _>("name"),
            "location": row.get::<String, _>("location"),
            "cityId": item_city.map(|u| u.to_string()),
            "phone": row.try_get::<Option<String>, _>("phone").ok().flatten(),
            "status": row.get::<String, _>("status"),
            "itemCount": row.try_get::<i32, _>("itemCount").unwrap_or(0),
        });
        if has_gps {
            if let Some((plat, plng)) = pin {
                let d = listing::haversine_km(lat, lng, plat, plng);
                value["distanceKm"] = json!((d * 10.0).round() / 10.0);
            }
        }
        scored.push((
            value.get("distanceKm").and_then(|v| v.as_f64()).unwrap_or(f64::MAX),
            value,
        ));
    }
    scored.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
    Ok(Json(scored.into_iter().take(100).map(|(_, v)| v).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct BusinessFilter { business_id:Option<Uuid> }

async fn my_items(State(state): State<AppState>, user: AuthUser,Query(filter):Query<BusinessFilter>) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE "ownerId" = $1 AND ($2::uuid IS NULL OR "businessId"=$2) ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .bind(uid)
    .bind(filter.business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
}

async fn get_item(State(state): State<AppState>, Path(id): Path<String>) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&id)?;
    let mut tx = state.db.begin().await?;
    booking::expire_holds(&mut tx).await?;
    tx.commit().await?;
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;

    let booked = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE "itemId" = $1
           AND status::text IN ('TEMP_HOLD','PAYMENT_PENDING','PENDING','PENDING_OWNER_CONFIRMATION','CONFIRMED','ACTIVE','RETURN_PENDING')
           AND (status::text NOT IN ('TEMP_HOLD','PAYMENT_PENDING') OR "holdExpiresAt" IS NULL OR "holdExpiresAt" > NOW())
           ORDER BY "startTime" ASC LIMIT 200"#
    ))
    .bind(rid)
    .fetch_all(&state.db)
    .await?;

    let mut item = item_json(&row);
    if let Some(obj) = item.as_object_mut() {
        obj.insert(
            "bookedRanges".into(),
            json!(booked
                .iter()
                .map(|r| json!({
                    "start": crate::common::pg::date_json(r, "startTime"),
                    "end": crate::common::pg::date_json(r, "endTime"),
                    "quantity": r.get::<i32,_>("quantity"),
                }))
                .collect::<Vec<_>>()),
        );
    }
    Ok(Json(item))
}

async fn create_item(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let input = listing::Listing::parse(&body)?;
    let mut tx=state.db.begin().await?;
    validate_business(&mut tx,input.business_id,uid).await?;
    if input.business_id.is_none() {return Err(AppError::BadRequest("Select your verified rental business".into()));}
    if input.pickup_address.trim().is_empty() {return Err(AppError::BadRequest("Provide the pickup address".into()));}
    let pin = listing::parse_pin(input.pickup_lat, input.pickup_lng)?;
    let (pickup_lat, pickup_lng) = resolve_pickup_pin(&mut tx, input.business_id, pin).await?;
    sqlx::query(
        r#"INSERT INTO rental_items (id, "ownerId", name, description, "imageUrl", "imageUrls", "hourlyRate", "dailyRate", "minHoursToRent", "isAvailable",
          "businessId",quantity,"pickupAddress","deliveryAvailable","deliveryFee","depositPerUnit","pickupLat","pickupLng","advanceAmount",
          "advancePercent","pickupInstructions","lateFeePerHour",condition,category,"cancellationPolicy","availableFrom","availableUntil",
          "availableWeekdays","slotStartMinute","slotEndMinute")
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(&input.name)
    .bind(&input.description)
    .bind(&input.image_url)
    .bind(input.image_urls_json())
    .bind(input.hourly())
    .bind(input.daily())
    .bind(input.min_hours_to_rent)
    .bind(input.business_id).bind(input.quantity).bind(input.pickup_address.trim())
    .bind(input.delivery_available).bind(input.delivery()).bind(input.deposit())
    .bind(pickup_lat).bind(pickup_lng).bind(input.advance())
    .bind(input.percent()).bind(input.pickup_instructions.trim()).bind(input.late_fee())
    .bind(&input.condition).bind(&input.category).bind(&input.cancellation_policy)
    .bind(input.available_from).bind(input.available_until).bind(&input.available_weekdays)
    .bind(input.slot_start_minute).bind(input.slot_end_minute)
    .execute(&mut *tx)
    .await?;
    fill_business_city_from_pin(&mut tx, input.business_id, pickup_lat, pickup_lng).await?;
    tx.commit().await?;
    get_item(State(state), Path(id.to_string())).await
}

async fn update_item(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let item_id = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id=$1 AND "ownerId"=$2 FOR UPDATE"#
    ))
    .bind(item_id)
    .bind(uid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;
    let mut merged = item_json(&row);
    for key in ["hourlyRate", "dailyRate", "deliveryFee", "depositPerUnit", "advanceAmount", "advancePercent", "lateFeePerHour"] {
        if let Some(number) = merged[key].as_str().and_then(|s| s.parse::<f64>().ok()) {
            merged[key] = json!(number);
        }
    }
    let fields = body
        .as_object()
        .ok_or_else(|| AppError::BadRequest("Invalid rental listing".into()))?;
    for (key, value) in fields {
        merged[key] = value.clone();
    }
    let input = listing::Listing::parse(&merged)?;
    let pin = listing::parse_pin(input.pickup_lat, input.pickup_lng)?;
    let (pickup_lat, pickup_lng) = if let Some(pin) = pin {
        pin
    } else {
        match (
            row.try_get::<Option<f64>, _>("pickupLat").ok().flatten(),
            row.try_get::<Option<f64>, _>("pickupLng").ok().flatten(),
        ) {
            (Some(a), Some(b)) => (a, b),
            _ => resolve_pickup_pin(&mut tx, input.business_id, None).await?,
        }
    };
    if input.business_id!=row.get::<Option<Uuid>,_>("businessId") {
        if row.get::<Option<Uuid>,_>("businessId").is_some() || input.business_id.is_none() {
            return Err(AppError::BadRequest("A listed item's business cannot be reassigned".into()));
        }
        validate_business(&mut tx,input.business_id,uid).await?;
    }
    if input.quantity<row.get::<i32,_>("quantity") {
        let booked:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM rental_reservations WHERE "itemId"=$1 AND status::text IN ('TEMP_HOLD','PAYMENT_PENDING','PENDING','PENDING_OWNER_CONFIRMATION','CONFIRMED','ACTIVE','RETURN_PENDING') AND (status::text NOT IN ('TEMP_HOLD','PAYMENT_PENDING') OR "holdExpiresAt" IS NULL OR "holdExpiresAt" > NOW()))"#)
            .bind(item_id).fetch_one(&mut *tx).await?;
        if booked {return Err(AppError::Conflict("Resolve confirmed and active rentals before reducing inventory".into()));}
    }
    sqlx::query(
        r#"UPDATE rental_items SET name=$1,description=$2,"imageUrl"=$3,"imageUrls"=$4,"hourlyRate"=$5,
        "dailyRate"=$6,"minHoursToRent"=$7,"isAvailable"=$8,"updatedAt"=NOW(),"businessId"=$10,
        quantity=$11,"pickupAddress"=$12,"deliveryAvailable"=$13,"deliveryFee"=$14,"depositPerUnit"=$15,
        "pickupLat"=$16,"pickupLng"=$17,"advanceAmount"=$18,"advancePercent"=$19,"pickupInstructions"=$20,
        "lateFeePerHour"=$21,condition=$22,category=$23,"cancellationPolicy"=$24,"availableFrom"=$25,
        "availableUntil"=$26,"availableWeekdays"=$27,"slotStartMinute"=$28,"slotEndMinute"=$29 WHERE id=$9"#,
    )
    .bind(&input.name)
    .bind(&input.description)
    .bind(&input.image_url)
    .bind(input.image_urls_json())
    .bind(input.hourly())
    .bind(input.daily())
    .bind(input.min_hours_to_rent)
    .bind(input.is_available)
    .bind(item_id)
    .bind(input.business_id).bind(input.quantity).bind(input.pickup_address.trim())
    .bind(input.delivery_available).bind(input.delivery()).bind(input.deposit())
    .bind(pickup_lat).bind(pickup_lng).bind(input.advance())
    .bind(input.percent()).bind(input.pickup_instructions.trim()).bind(input.late_fee())
    .bind(&input.condition).bind(&input.category).bind(&input.cancellation_policy)
    .bind(input.available_from).bind(input.available_until).bind(&input.available_weekdays)
    .bind(input.slot_start_minute).bind(input.slot_end_minute)
    .execute(&mut *tx)
    .await?;
    fill_business_city_from_pin(&mut tx, input.business_id, pickup_lat, pickup_lng).await?;
    tx.commit().await?;
    get_item(State(state), Path(id)).await
}

#[derive(Deserialize)]
struct ReserveBody {
    startTime: String,
    endTime: String,
    #[serde(default="one")]
    quantity:i32,
    #[serde(default="pickup")]
    fulfillment:String,
    #[serde(default)]
    deliveryAddress:String,
}
fn one()->i32 {1}
fn pickup()->String {"PICKUP".into()}

async fn create_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<ReserveBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let item_id = Uuid::parse_str(&id)?;
    let res_id = Uuid::new_v4();
    let (start, end) = policy::parse_window(&body.startTime, &body.endTime, chrono::Utc::now())?;
    let mut tx = state.db.begin().await?;

    let item = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id = $1 FOR UPDATE"#
    ))
    .bind(item_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;

    let owner_id = item.get::<Uuid, _>("ownerId");
    validate_business(&mut tx,item.get("businessId"),owner_id).await?;
    if owner_id == uid {
        return Err(AppError::BadRequest(
            "You cannot reserve your own item.".into(),
        ));
    }
    if !item.get::<bool, _>("isAvailable") {
        return Err(AppError::BadRequest(
            "This item is currently listed as unavailable.".into(),
        ));
    }
    listing::listing_window_ok(
        item.try_get::<Option<NaiveDate>, _>("availableFrom")
            .ok()
            .flatten(),
        item.try_get::<Option<NaiveDate>, _>("availableUntil")
            .ok()
            .flatten(),
        &item
            .try_get::<Vec<i16>, _>("availableWeekdays")
            .unwrap_or_else(|_| vec![1, 2, 3, 4, 5, 6, 7]),
        item.try_get::<Option<i32>, _>("slotStartMinute")
            .ok()
            .flatten(),
        item.try_get::<Option<i32>, _>("slotEndMinute")
            .ok()
            .flatten(),
        start,
        end,
    )?;

    let hourly = item
        .try_get::<rust_decimal::Decimal, _>("hourlyRate")
        .ok()
        .unwrap_or_default();
    let daily = item
        .try_get::<Option<rust_decimal::Decimal>, _>("dailyRate")
        .ok()
        .flatten();
    if body.quantity<1 || body.quantity>item.get::<i32,_>("quantity") || !["PICKUP","DELIVERY"].contains(&body.fulfillment.as_str()) {
        return Err(AppError::BadRequest("Select an available quantity and pickup or delivery".into()));
    }
    if body.fulfillment=="DELIVERY" && (!item.get::<bool,_>("deliveryAvailable") || body.deliveryAddress.trim().is_empty() || body.deliveryAddress.len()>2000) {
        return Err(AppError::BadRequest("Delivery requires an address and an item offering delivery".into()));
    }
    let unit = policy::price(start, end, hourly, daily, item.get("minHoursToRent"))?;
    let rent=unit*rust_decimal::Decimal::from(body.quantity);
    let deposit=item.get::<rust_decimal::Decimal,_>("depositPerUnit")*rust_decimal::Decimal::from(body.quantity);
    let delivery=if body.fulfillment=="DELIVERY" {item.get::<rust_decimal::Decimal,_>("deliveryFee")} else {rust_decimal::Decimal::ZERO};
    let total=rent+deposit+delivery;
    if total>rust_decimal::Decimal::from(99_999_999) {return Err(AppError::BadRequest("Rental total is outside the supported range".into()));}
    let address=if body.fulfillment=="DELIVERY" {body.deliveryAddress.trim().to_string()} else {item.get::<String,_>("pickupAddress")};
    let cancel_policy = item
        .try_get::<String, _>("cancellationPolicy")
        .unwrap_or_else(|_| "FLEXIBLE".into());
    let breakdown=json!({"unitRental":unit,"rent":rent,"delivery":delivery,"deposit":deposit,"total":total,
        "itemName":item.get::<String,_>("name"),"depositTerms":policy::deposit_terms(&cancel_policy),
        "cancellationPolicy":cancel_policy,
        "lateFeePerHour":item.try_get::<rust_decimal::Decimal,_>("lateFeePerHour").unwrap_or_default()});
    booking::expire_holds(&mut tx).await?;
    ensure_available(&mut tx, item_id, start.naive_utc(), end.naive_utc(),body.quantity,item.get("quantity"), None).await?;

    let listed = item
        .try_get::<rust_decimal::Decimal, _>("advanceAmount")
        .unwrap_or(rust_decimal::Decimal::ZERO)
        * rust_decimal::Decimal::from(body.quantity);
    let percent = item
        .try_get::<rust_decimal::Decimal, _>("advancePercent")
        .unwrap_or(rust_decimal::Decimal::ZERO);
    let advance = booking::advance_due(listed, percent, total);
    let remaining = (total - advance).max(rust_decimal::Decimal::ZERO);
    let pay_now = advance >= rust_decimal::Decimal::ONE && booking::gateway_configured(&state);
    let (status, payment_status, hold_expires) = if pay_now {
        (
            "TEMP_HOLD",
            "PAYMENT_PENDING",
            Some(booking::hold_deadline(chrono::Utc::now())),
        )
    } else {
        ("PENDING_OWNER_CONFIRMATION", "NONE", None)
    };
    let mut breakdown = breakdown;
    breakdown["advance"] = json!(advance);
    breakdown["remaining"] = json!(remaining);
    breakdown["holdMinutes"] = json!(booking::HOLD_MINUTES);

    sqlx::query(
        r#"INSERT INTO rental_reservations (id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status,
          quantity,fulfillment,"fulfillmentAddress","priceBreakdown","paymentStatus","holdExpiresAt","advanceAmount","remainingAmount")
           VALUES ($1, $2, $3, $4, $5, $6, $7::rental_reservations_status_enum,$8,$9,$10,$11,$12,$13,$14,$15)"#,
    )
    .bind(res_id)
    .bind(item_id)
    .bind(uid)
    .bind(start.naive_utc())
    .bind(end.naive_utc())
    .bind(total)
    .bind(status)
    .bind(body.quantity).bind(&body.fulfillment).bind(address).bind(breakdown)
    .bind(payment_status)
    .bind(hold_expires)
    .bind(advance)
    .bind(remaining)
    .execute(&mut *tx)
    .await?;
    if status == "PENDING_OWNER_CONFIRMATION" {
        crate::outbox::notify(
            &mut tx,
            res_id,
            owner_id,
            "New rental request",
            "A customer requested your item. Review its dates and confirm availability.",
            json!({"type":"rental_request","reservationId":res_id,"audience":"owner"}),
        )
        .await?;
    }
    tx.commit().await?;

    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(res_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(reservation_json_view(&row, Some(ReservationView::Renter))))
}

async fn my_reservations(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    booking::expire_holds(&mut tx).await?;
    tx.commit().await?;
    let rows = sqlx::query(&format!(
        r#"SELECT r.*,r.status::text AS status,
            to_jsonb(i) AS item FROM rental_reservations r JOIN rental_items i ON i.id=r."itemId"
            WHERE r."renterId" = $1 ORDER BY r."createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| reservation_json_view(r, Some(ReservationView::Renter))).collect()))
}

async fn owner_reservations(
    State(state): State<AppState>,
    user: AuthUser,
    Query(filter):Query<BusinessFilter>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    booking::expire_holds(&mut tx).await?;
    tx.commit().await?;
    let rows = sqlx::query(&format!(
        r#"SELECT r.*,r.status::text AS status,
            to_jsonb(i) AS item, jsonb_build_object('id',u.id,'name',u.name) AS renter
           FROM rental_reservations r
           JOIN rental_items i ON i.id = r."itemId"
           JOIN users u ON u.id = r."renterId"
           WHERE i."ownerId" = $1 AND ($2::uuid IS NULL OR i."businessId"=$2)
           ORDER BY r."createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .bind(filter.business_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(|r| reservation_json_view(r, Some(ReservationView::Owner))).collect()))
}
async fn confirm_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "CONFIRMED").await
}

async fn reject_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "REJECTED").await
}

async fn start_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    fulfillment::change(&state,&user,&res_id,"handover").await
}

async fn complete_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    fulfillment::change(&state,&user,&res_id,"return").await
}

async fn cancel_reservation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    update_reservation_status(&state, &user, &res_id, "CANCELLED").await
}

async fn update_reservation_status(
    state: &AppState,
    user: &AuthUser,
    res_id: &str,
    status: &str,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(res_id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    // Every decision takes the item lock before the reservation lock. This
    // serializes confirm/cancel/start/return with reserve and competing confirms.
    let item = sqlx::query(
        r#"SELECT i.id, i."ownerId", i."isAvailable",i.quantity,i."businessId",i."cancellationPolicy" FROM rental_items i
        JOIN rental_reservations r ON r."itemId" = i.id WHERE r.id = $1 FOR UPDATE OF i"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Reservation not found".into()))?;
    booking::expire_holds(&mut tx).await?;
    let reservation = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1 FOR UPDATE"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    policy::transition(
        &reservation.get::<String, _>("status"),
        status,
        item.get::<Uuid, _>("ownerId") == uid,
        reservation.get::<Uuid, _>("renterId") == uid,
    )?;
    if status == "CONFIRMED" {
        validate_business(&mut tx,item.get("businessId"),item.get("ownerId")).await?;
        if !item.get::<bool, _>("isAvailable") {
            return Err(AppError::Conflict(
                "This item is no longer available".into(),
            ));
        }
        let start = reservation.get::<chrono::NaiveDateTime, _>("startTime");
        let end = reservation.get::<chrono::NaiveDateTime, _>("endTime");
        if end <= chrono::Utc::now().naive_utc() {
            return Err(AppError::Conflict("This reservation has expired".into()));
        }
        ensure_available(&mut tx, item.get("id"), start, end,reservation.get("quantity"),item.get("quantity"), Some(rid)).await?;
    }
    if status=="CANCELLED" && (reservation.get::<Option<chrono::DateTime<chrono::Utc>>,_>("ownerHandedOverAt").is_some()
        || reservation.get::<Option<chrono::DateTime<chrono::Utc>>,_>("renterCollectedAt").is_some()) {
        return Err(AppError::Conflict("Handover has begun. Record the return to close this rental".into()));
    }
    if status == "CONFIRMED" {
        sqlx::query(
            r#"UPDATE rental_reservations
               SET status = $1::rental_reservations_status_enum,
                   "handoverOtp" = $3,
                   "returnOtp" = $4,
                   "holdExpiresAt" = NULL,
                   "updatedAt" = NOW()
               WHERE id = $2"#,
        )
        .bind(status)
        .bind(rid)
        .bind(booking::otp())
        .bind(booking::otp())
        .execute(&mut *tx)
        .await?;
    } else if status == "CANCELLED" {
        let policy = item
            .try_get::<String, _>("cancellationPolicy")
            .unwrap_or_else(|_| "FLEXIBLE".into());
        let start = reservation
            .get::<chrono::NaiveDateTime, _>("startTime")
            .and_utc();
        let advance = reservation
            .try_get::<rust_decimal::Decimal, _>("advanceAmount")
            .unwrap_or(rust_decimal::Decimal::ZERO);
        let refund = policy::cancel_refund(
            &policy,
            &reservation.get::<String, _>("status"),
            start,
            chrono::Utc::now(),
            advance,
        );
        let mut breakdown = reservation.get::<Value, _>("priceBreakdown");
        if let Some(obj) = breakdown.as_object_mut() {
            obj.insert("cancellationRefund".into(), json!(refund));
            obj.insert("cancellationPolicy".into(), json!(policy));
        }
        sqlx::query(
            r#"UPDATE rental_reservations
               SET status = $1::rental_reservations_status_enum,
                   "priceBreakdown" = $3,
                   "updatedAt" = NOW()
               WHERE id = $2"#,
        )
        .bind(status)
        .bind(rid)
        .bind(breakdown)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(r#"UPDATE rental_reservations SET status = $1::rental_reservations_status_enum, "updatedAt" = NOW() WHERE id = $2"#)
            .bind(status)
            .bind(rid)
            .execute(&mut *tx)
            .await?;
    }
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    let recipient = if status == "CANCELLED" {
        item.get("ownerId")
    } else {
        reservation.get("renterId")
    };
    crate::outbox::notify(
        &mut tx,
        rid,
        recipient,
        "Rental status update",
        &format!("Your rental is now {}.", status.to_lowercase()),
        json!({"type":"rental_status","reservationId":rid,"status":status,"audience":if status=="CANCELLED" {"owner"} else {"renter"}}),
    )
    .await?;
    tx.commit().await?;
    let view = if item.get::<Uuid, _>("ownerId") == uid {
        ReservationView::Owner
    } else {
        ReservationView::Renter
    };
    Ok(Json(reservation_json_view(&row, Some(view))))
}

async fn ensure_available(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    item_id: Uuid,
    start: chrono::NaiveDateTime,
    end: chrono::NaiveDateTime,
    requested:i32,
    capacity:i32,
    exclude: Option<Uuid>,
) -> AppResult<()> {
    // Check peak concurrent units, not the sum of non-overlapping reservations.
    // An overdue active rental keeps its stock until both sides record return.
    booking::expire_holds(tx).await?;
    let used: i64 = sqlx::query_scalar(r#"WITH booked AS (
        SELECT "startTime" AS start,CASE WHEN status='ACTIVE' AND "endTime"<(NOW() AT TIME ZONE 'UTC')
          THEN 'infinity'::timestamp ELSE "endTime" END AS finish,quantity
        FROM rental_reservations WHERE "itemId"=$1
          AND ($4::uuid IS NULL OR id <> $4)
          AND status::text IN ('TEMP_HOLD','PAYMENT_PENDING','PENDING','PENDING_OWNER_CONFIRMATION','CONFIRMED','ACTIVE')
          AND (status::text NOT IN ('TEMP_HOLD','PAYMENT_PENDING') OR "holdExpiresAt" IS NULL OR "holdExpiresAt" > NOW())
          AND ("ownerReturnedAt" IS NULL OR "renterReturnedAt" IS NULL)),
        points AS (SELECT $2::timestamp AS t UNION SELECT start FROM booked WHERE start>$2 AND start<$3)
        SELECT COALESCE(MAX((SELECT COALESCE(SUM(quantity),0) FROM booked WHERE start<=p.t AND finish>p.t)),0)::bigint FROM points p"#)
        .bind(item_id).bind(start).bind(end).bind(exclude).fetch_one(&mut **tx).await?;
    if used+i64::from(requested)>i64::from(capacity) {
        return Err(AppError::Conflict(
            "There are not enough available units for this interval".into(),
        ));
    }
    Ok(())
}

fn item_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "ownerId": row.get::<Uuid, _>("ownerId").to_string(),
        "businessId": row.get::<Option<Uuid>,_>("businessId"),
        "quantity": row.get::<i32,_>("quantity"),
        "pickupAddress": row.get::<String,_>("pickupAddress"),
        "deliveryAvailable": row.get::<bool,_>("deliveryAvailable"),
        "deliveryFee": row.get::<rust_decimal::Decimal,_>("deliveryFee"),
        "depositPerUnit": row.get::<rust_decimal::Decimal,_>("depositPerUnit"),
        "advanceAmount": row.try_get::<rust_decimal::Decimal,_>("advanceAmount").unwrap_or(rust_decimal::Decimal::ZERO),
        "advancePercent": row.try_get::<rust_decimal::Decimal,_>("advancePercent").unwrap_or(rust_decimal::Decimal::ZERO),
        "pickupInstructions": row.try_get::<String,_>("pickupInstructions").unwrap_or_default(),
        "lateFeePerHour": row.try_get::<rust_decimal::Decimal,_>("lateFeePerHour").unwrap_or(rust_decimal::Decimal::ZERO),
        "condition": row.try_get::<String,_>("condition").unwrap_or_else(|_| "GOOD".into()),
        "category": row.try_get::<String,_>("category").unwrap_or_else(|_| "OTHER".into()),
        "cancellationPolicy": row.try_get::<String,_>("cancellationPolicy").unwrap_or_else(|_| "FLEXIBLE".into()),
        "availableFrom": row.try_get::<Option<NaiveDate>,_>("availableFrom").ok().flatten().map(|d| d.to_string()),
        "availableUntil": row.try_get::<Option<NaiveDate>,_>("availableUntil").ok().flatten().map(|d| d.to_string()),
        "availableWeekdays": row.try_get::<Vec<i16>,_>("availableWeekdays").unwrap_or_else(|_| vec![1, 2, 3, 4, 5, 6, 7]),
        "slotStartMinute": row.try_get::<Option<i32>,_>("slotStartMinute").ok().flatten(),
        "slotEndMinute": row.try_get::<Option<i32>,_>("slotEndMinute").ok().flatten(),
        "pickupLat": row.try_get::<Option<f64>, _>("pickupLat").ok().flatten(),
        "pickupLng": row.try_get::<Option<f64>, _>("pickupLng").ok().flatten(),
        "name": row.get::<String, _>("name"),
        "description": row.get::<Option<String>, _>("description"),
        "imageUrl": row.get::<Option<String>, _>("imageUrl"),
        "imageUrls": row.try_get::<Value, _>("imageUrls").ok().unwrap_or_else(|| json!([])),
        "hourlyRate": row.get::<rust_decimal::Decimal, _>("hourlyRate"),
        "dailyRate": row.try_get::<Option<rust_decimal::Decimal>, _>("dailyRate").ok().flatten(),
        "minHoursToRent": row.get::<i32, _>("minHoursToRent"),
        "isAvailable": row.get::<bool, _>("isAvailable"),
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "updatedAt": crate::common::pg::date_json(row,"updatedAt"),
    })
}

pub(super) enum ReservationView {
    Renter,
    Owner,
}

fn reservation_json(row: &sqlx::postgres::PgRow) -> Value {
    reservation_json_view(row, None)
}

pub(super) fn reservation_json_view(row: &sqlx::postgres::PgRow, view: Option<ReservationView>) -> Value {
    let mut value = json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "itemId": row.get::<Uuid, _>("itemId").to_string(),
        "renterId": row.get::<Uuid, _>("renterId").to_string(),
        "startTime": crate::common::pg::date_json(row, "startTime"),
        "endTime": crate::common::pg::date_json(row, "endTime"),
        "totalPrice": row.try_get::<rust_decimal::Decimal, _>("totalPrice").ok(),
        "status": row.get::<String, _>("status"),
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "item": row.try_get::<Value,_>("item").ok(),
        "renter": row.try_get::<Value,_>("renter").ok(),
        "quantity":row.get::<i32,_>("quantity"),"fulfillment":row.get::<String,_>("fulfillment"),
        "fulfillmentAddress":row.get::<String,_>("fulfillmentAddress"),"priceBreakdown":row.get::<Value,_>("priceBreakdown"),
        "ownerHandedOverAt":crate::common::pg::date_json(row,"ownerHandedOverAt"),
        "renterCollectedAt":crate::common::pg::date_json(row,"renterCollectedAt"),
        "ownerReturnedAt":crate::common::pg::date_json(row,"ownerReturnedAt"),
        "renterReturnedAt":crate::common::pg::date_json(row,"renterReturnedAt"),
        "ownerPaidAt":crate::common::pg::date_json(row,"ownerPaidAt"),"renterPaidAt":crate::common::pg::date_json(row,"renterPaidAt"),
        "ownerRefundedAt":crate::common::pg::date_json(row,"ownerRefundedAt"),"renterRefundedAt":crate::common::pg::date_json(row,"renterRefundedAt"),
        "paymentStatus": row.try_get::<String,_>("paymentStatus").ok().or_else(|| row.try_get::<Option<String>,_>("paymentStatus").ok().flatten()),
        "holdExpiresAt": crate::common::pg::date_json(row,"holdExpiresAt"),
        "advanceAmount": row.try_get::<rust_decimal::Decimal,_>("advanceAmount").ok(),
        "remainingAmount": row.try_get::<rust_decimal::Decimal,_>("remainingAmount").ok(),
        "lateFee": row.try_get::<rust_decimal::Decimal,_>("lateFee").ok(),
        "damageAmount": row.try_get::<rust_decimal::Decimal,_>("damageAmount").ok(),
    });
    if matches!(view, Some(ReservationView::Renter)) {
        value["handoverOtp"] = json!(row.try_get::<Option<String>,_>("handoverOtp").ok().flatten());
        value["returnOtp"] = json!(row.try_get::<Option<String>,_>("returnOtp").ok().flatten());
    }
    value
}

/// When a rental store was saved without a city (stale UUID dropped, or omitted),
/// pin it to the nearest live city so city-or-25km catalog matching can find it.
async fn fill_business_city_from_pin(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    business_id: Option<Uuid>,
    lat: f64,
    lng: f64,
) -> AppResult<()> {
    let Some(bid) = business_id else {
        return Ok(());
    };
    let rows = sqlx::query(
        r#"SELECT id, lat::float8 AS lat, lng::float8 AS lng FROM cities WHERE "isActive" = true"#,
    )
    .fetch_all(&mut **tx)
    .await?;
    let mut best: Option<(Uuid, f64)> = None;
    for row in &rows {
        let id = row.get::<Uuid, _>("id");
        let clat = row.get::<f64, _>("lat");
        let clng = row.get::<f64, _>("lng");
        if !clat.is_finite() || !clng.is_finite() {
            continue;
        }
        let d = listing::haversine_km(lat, lng, clat, clng);
        if d <= listing::MAX_RENTAL_RADIUS_KM && best.map(|(_, bd)| d < bd).unwrap_or(true) {
            best = Some((id, d));
        }
    }
    let Some((city, _)) = best else {
        return Ok(());
    };
    sqlx::query(r#"UPDATE businesses SET "cityId" = $1 WHERE id = $2 AND "cityId" IS NULL"#)
        .bind(city)
        .bind(bid)
        .execute(&mut **tx)
        .await?;
    Ok(())
}

async fn resolve_pickup_pin(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    business_id: Option<Uuid>,
    pin: Option<(f64, f64)>,
) -> AppResult<(f64, f64)> {
    if let Some(pin) = pin {
        return Ok(pin);
    }
    if let Some(bid) = business_id {
        if let Some(row) = sqlx::query(
            r#"SELECT c.lat::float8 AS lat, c.lng::float8 AS lng FROM businesses b JOIN cities c ON c.id = b."cityId" WHERE b.id = $1"#,
        )
        .bind(bid)
        .fetch_optional(&mut **tx)
        .await?
        {
            if let (Ok(lat), Ok(lng)) = (row.try_get::<f64, _>("lat"), row.try_get::<f64, _>("lng")) {
                if lat.is_finite() && lng.is_finite() {
                    return Ok((lat, lng));
                }
            }
        }
    }
    Err(AppError::BadRequest(
        "Set your business city so nearby customers can find this item".into(),
    ))
}

async fn validate_business(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,id:Option<Uuid>,owner:Uuid)->AppResult<()> {
    if let Some(id)=id {
        let valid:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='RENTAL' AND status='VERIFIED')"#)
            .bind(id).bind(owner).fetch_one(&mut **tx).await?;
        if !valid {return Err(AppError::Forbidden("A verified rental business on your account is required".into()));}
    }
    Ok(())
}
