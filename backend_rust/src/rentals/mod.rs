use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::{RENTAL_ITEM_COLS, RENTAL_RESERVATION_COLS};
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

mod listing;
mod policy;
mod fulfillment;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", get(list_items).post(create_item))
        .route("/my-items", get(my_items))
        .route("/reservations/my", get(my_reservations))
        .route("/reservations/owner", get(owner_reservations))
        .route("/reservations/{res_id}/ack/{action}", patch(fulfillment::acknowledge))
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

async fn list_items(State(state): State<AppState>) -> AppResult<Json<Vec<Value>>> {
    let rows = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE "isAvailable" = true
        AND (rental_items."businessId" IS NULL OR EXISTS(
            SELECT 1 FROM businesses b
            WHERE b.id = rental_items."businessId" AND b.status::text = 'VERIFIED'))
        ORDER BY "createdAt" DESC LIMIT 100"#
    ))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(item_json).collect()))
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
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_ITEM_COLS} FROM rental_items WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Item not found".into()))?;

    let booked = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE "itemId" = $1 AND status IN ('CONFIRMED', 'ACTIVE') ORDER BY "startTime" ASC LIMIT 200"#
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
    sqlx::query(
        r#"INSERT INTO rental_items (id, "ownerId", name, description, "imageUrl", "hourlyRate", "dailyRate", "minHoursToRent", "isAvailable",
          "businessId",quantity,"pickupAddress","deliveryAvailable","deliveryFee","depositPerUnit")
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true,$9,$10,$11,$12,$13,$14)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(&input.name)
    .bind(&input.description)
    .bind(&input.image_url)
    .bind(input.hourly())
    .bind(input.daily())
    .bind(input.min_hours_to_rent)
    .bind(input.business_id).bind(input.quantity).bind(input.pickup_address.trim())
    .bind(input.delivery_available).bind(input.delivery()).bind(input.deposit())
    .execute(&mut *tx)
    .await?;
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
    for key in ["hourlyRate", "dailyRate", "deliveryFee", "depositPerUnit"] {
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
    if input.business_id!=row.get::<Option<Uuid>,_>("businessId") {
        if row.get::<Option<Uuid>,_>("businessId").is_some() || input.business_id.is_none() {
            return Err(AppError::BadRequest("A listed item's business cannot be reassigned".into()));
        }
        validate_business(&mut tx,input.business_id,uid).await?;
    }
    if input.quantity<row.get::<i32,_>("quantity") {
        let booked:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM rental_reservations WHERE "itemId"=$1 AND status IN ('CONFIRMED','ACTIVE'))"#)
            .bind(item_id).fetch_one(&mut *tx).await?;
        if booked {return Err(AppError::Conflict("Resolve confirmed and active rentals before reducing inventory".into()));}
    }
    sqlx::query(
        r#"UPDATE rental_items SET name=$1,description=$2,"imageUrl"=$3,"hourlyRate"=$4,
        "dailyRate"=$5,"minHoursToRent"=$6,"isAvailable"=$7,"updatedAt"=NOW(),"businessId"=$9,
        quantity=$10,"pickupAddress"=$11,"deliveryAvailable"=$12,"deliveryFee"=$13,"depositPerUnit"=$14 WHERE id=$8"#,
    )
    .bind(&input.name)
    .bind(&input.description)
    .bind(&input.image_url)
    .bind(input.hourly())
    .bind(input.daily())
    .bind(input.min_hours_to_rent)
    .bind(input.is_available)
    .bind(item_id)
    .bind(input.business_id).bind(input.quantity).bind(input.pickup_address.trim())
    .bind(input.delivery_available).bind(input.delivery()).bind(input.deposit())
    .execute(&mut *tx)
    .await?;
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
    let breakdown=json!({"unitRental":unit,"rent":rent,"delivery":delivery,"deposit":deposit,"total":total,
        "itemName":item.get::<String,_>("name"),"depositTerms":"Full refundable deposit; no automatic deductions. Cancel before handover for a full refund of amounts paid."});
    ensure_available(&mut tx, item_id, start.naive_utc(), end.naive_utc(),body.quantity,item.get("quantity")).await?;

    sqlx::query(
        r#"INSERT INTO rental_reservations (id, "itemId", "renterId", "startTime", "endTime", "totalPrice", status,
          quantity,fulfillment,"fulfillmentAddress","priceBreakdown")
           VALUES ($1, $2, $3, $4, $5, $6, 'PENDING',$7,$8,$9,$10)"#,
    )
    .bind(res_id)
    .bind(item_id)
    .bind(uid)
    .bind(start.naive_utc())
    .bind(end.naive_utc())
    .bind(total)
    .bind(body.quantity).bind(&body.fulfillment).bind(address).bind(breakdown)
    .execute(&mut *tx)
    .await?;
    crate::outbox::notify(
        &mut tx,
        res_id,
        owner_id,
        "New rental request",
        "A customer requested your item. Review its dates and confirm availability.",
        json!({"type":"rental_request","reservationId":res_id,"audience":"owner"}),
    )
    .await?;
    tx.commit().await?;

    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(res_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(reservation_json(&row)))
}

async fn my_reservations(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT r.*,r.status::text AS status,
            to_jsonb(i) AS item FROM rental_reservations r JOIN rental_items i ON i.id=r."itemId"
            WHERE r."renterId" = $1 ORDER BY r."createdAt" DESC LIMIT 50"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(reservation_json).collect()))
}

async fn owner_reservations(
    State(state): State<AppState>,
    user: AuthUser,
    Query(filter):Query<BusinessFilter>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
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
    Ok(Json(rows.iter().map(reservation_json).collect()))
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
        r#"SELECT i.id, i."ownerId", i."isAvailable",i.quantity,i."businessId" FROM rental_items i
        JOIN rental_reservations r ON r."itemId" = i.id WHERE r.id = $1 FOR UPDATE OF i"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Reservation not found".into()))?;
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
        ensure_available(&mut tx, item.get("id"), start, end,reservation.get("quantity"),item.get("quantity")).await?;
    }
    if status=="CANCELLED" && (reservation.get::<Option<chrono::DateTime<chrono::Utc>>,_>("ownerHandedOverAt").is_some()
        || reservation.get::<Option<chrono::DateTime<chrono::Utc>>,_>("renterCollectedAt").is_some()) {
        return Err(AppError::Conflict("Handover has begun. Record the return to close this rental".into()));
    }
    sqlx::query(r#"UPDATE rental_reservations SET status = $1::rental_reservations_status_enum, "updatedAt" = NOW() WHERE id = $2"#)
        .bind(status)
        .bind(rid)
        .execute(&mut *tx)
        .await?;
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
    Ok(Json(reservation_json(&row)))
}

async fn ensure_available(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    item_id: Uuid,
    start: chrono::NaiveDateTime,
    end: chrono::NaiveDateTime,
    requested:i32,
    capacity:i32,
) -> AppResult<()> {
    // Check peak concurrent units, not the sum of non-overlapping reservations.
    // An overdue active rental keeps its stock until both sides record return.
    let used: i64 = sqlx::query_scalar(r#"WITH booked AS (
        SELECT "startTime" AS start,CASE WHEN status='ACTIVE' AND "endTime"<(NOW() AT TIME ZONE 'UTC')
          THEN 'infinity'::timestamp ELSE "endTime" END AS finish,quantity
        FROM rental_reservations WHERE "itemId"=$1 AND status IN ('CONFIRMED','ACTIVE')
          AND ("ownerReturnedAt" IS NULL OR "renterReturnedAt" IS NULL)),
        points AS (SELECT $2::timestamp AS t UNION SELECT start FROM booked WHERE start>$2 AND start<$3)
        SELECT COALESCE(MAX((SELECT COALESCE(SUM(quantity),0) FROM booked WHERE start<=p.t AND finish>p.t)),0)::bigint FROM points p"#)
        .bind(item_id).bind(start).bind(end).fetch_one(&mut **tx).await?;
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
        "name": row.get::<String, _>("name"),
        "description": row.get::<Option<String>, _>("description"),
        "imageUrl": row.get::<Option<String>, _>("imageUrl"),
        "hourlyRate": row.get::<rust_decimal::Decimal, _>("hourlyRate"),
        "dailyRate": row.try_get::<Option<rust_decimal::Decimal>, _>("dailyRate").ok().flatten(),
        "minHoursToRent": row.get::<i32, _>("minHoursToRent"),
        "isAvailable": row.get::<bool, _>("isAvailable"),
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "updatedAt": crate::common::pg::date_json(row,"updatedAt"),
    })
}

fn reservation_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
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
    })
}

async fn validate_business(tx:&mut sqlx::Transaction<'_,sqlx::Postgres>,id:Option<Uuid>,owner:Uuid)->AppResult<()> {
    if let Some(id)=id {
        let valid:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='RENTAL' AND status='VERIFIED')"#)
            .bind(id).bind(owner).fetch_one(&mut **tx).await?;
        if !valid {return Err(AppError::Forbidden("A verified rental business on your account is required".into()));}
    }
    Ok(())
}
