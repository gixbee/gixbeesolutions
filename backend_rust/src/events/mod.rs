use axum::{extract::{Path, Query, State}, routing::{get, post}, Json, Router};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;
use crate::{error::{AppError, AppResult}, middleware::auth::AuthUser, state::AppState};

mod quotes;
pub const SERVICES: [&str;8] = ["HALL","CATERING","DECORATION","PHOTOGRAPHY","DJ","MAKEUP","MEHENDI","INVITATIONS"];

pub fn routes() -> Router<AppState> {
    Router::new().route("/",get(my_plans).post(create_plan))
        .route("/vendor/inbox",get(vendor_inbox))
        .route("/quotes/{id}/{action}",post(quotes::action))
        .route("/{id}",get(detail))
        .route("/{id}/quotes",post(quotes::offer))
        .route("/{id}/cancel",post(cancel_plan))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct PlanInput {
    event_type:String, start_time:String, end_time:String, guest_count:i32,
    location:String, city_id:Option<Uuid>, services:Vec<String>, #[serde(default)] notes:String,
}

async fn create_plan(State(state):State<AppState>,user:AuthUser,Json(mut input):Json<PlanInput>)->AppResult<Json<Value>> {
    let start=parse_time(&input.start_time)?;let end=parse_time(&input.end_time)?;
    input.services.sort();input.services.dedup();
    if start<=Utc::now() || end<=start || end-start>chrono::Duration::days(14)
        || start>Utc::now()+chrono::Duration::days(730) || !(1..=100000).contains(&input.guest_count)
        || input.event_type.trim().is_empty() || input.event_type.len()>100 || input.location.trim().is_empty()
        || input.location.len()>2000 || input.notes.len()>5000 || input.services.is_empty()
        || input.services.iter().any(|s|!SERVICES.contains(&s.as_str())) {
        return Err(AppError::BadRequest("Provide future event times, an address, guest count and supported services".into()));
    }
    let id=Uuid::new_v4();let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    let active_city:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM cities WHERE id=$1 AND "isActive"=true)"#)
        .bind(input.city_id).fetch_one(&mut *tx).await?;
    if !active_city {return Err(AppError::BadRequest("Select an active serviceable city for the event".into()));}
    sqlx::query(r#"INSERT INTO event_plans (id,"customerId","eventType","startTime","endTime","guestCount",location,"cityId",services,notes)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)"#)
        .bind(id).bind(uid).bind(input.event_type.trim()).bind(start).bind(end).bind(input.guest_count)
        .bind(input.location.trim()).bind(input.city_id).bind(json!(input.services)).bind(input.notes.trim()).execute(&mut *tx).await?;
    let vendors=sqlx::query(r#"SELECT DISTINCT "ownerId" FROM businesses WHERE type='SERVICE' AND status='VERIFIED'
        AND "ownerId"<>$1 AND ($2::uuid IS NULL OR "cityId"=$2)
        AND ("serviceType"::text=ANY($3) OR "eventServices" ?| $3) LIMIT 200"#)
        .bind(uid).bind(input.city_id).bind(&input.services).fetch_all(&mut *tx).await?;
    for vendor in vendors {
        crate::outbox::notify(&mut tx,id,vendor.get("ownerId"),"New event enquiry",
            "An event needs your services. Review its date and send a quote from your business dashboard.",
            json!({"type":"event_enquiry","planId":id})).await?;
    }
    // Hall enquiries: one row per eligible HALL business (idempotent).
    let _ = crate::hall_enquiries::ensure_enquiries_for_plan(
        &mut tx,
        id,
        uid,
        input.city_id,
        &input.services,
    )
    .await?;
    tx.commit().await?;
    detail(State(state),user,Path(id.to_string())).await
}

async fn my_plans(State(state):State<AppState>,user:AuthUser)->AppResult<Json<Vec<Value>>> {
    let rows=sqlx::query(r#"SELECT to_jsonb(p) || jsonb_build_object('confirmedServices',
        (SELECT count(*) FROM event_quotes q WHERE q."planId"=p.id AND q.status IN ('CONFIRMED','COMPLETED')),
        'completedServices',(SELECT count(*) FROM event_quotes q WHERE q."planId"=p.id AND q.status='COMPLETED')) AS data
        FROM event_plans p WHERE p."customerId"=$1 ORDER BY p."startTime" DESC LIMIT 100"#)
        .bind(Uuid::parse_str(&user.user_id)?).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(|r|r.get("data")).collect()))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct VendorQuery { business_id:Uuid }

async fn vendor_inbox(State(state):State<AppState>,user:AuthUser,Query(q):Query<VendorQuery>)->AppResult<Json<Vec<Value>>> {
    let uid=Uuid::parse_str(&user.user_id)?;
    let business=sqlx::query(r#"SELECT "serviceType"::text AS service,"eventServices","cityId",status::text AS status
        FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='SERVICE'"#)
        .bind(q.business_id).bind(uid).fetch_optional(&state.db).await?
        .ok_or_else(||AppError::NotFound("Service business not found on your account".into()))?;
    let verified=business.get::<String,_>("status")=="VERIFIED";
    let mut services=business.get::<Value,_>("eventServices").as_array().cloned().unwrap_or_default()
        .iter().filter_map(|v|v.as_str().map(str::to_owned)).collect::<Vec<_>>();
    if let Some(service)=business.get::<Option<String>,_>("service") {services.push(service);}
    let rows=sqlx::query(r#"SELECT to_jsonb(p) AS data FROM event_plans p WHERE p."customerId"<>$1
        AND (EXISTS(SELECT 1 FROM event_quotes q WHERE q."planId"=p.id AND q."businessId"=$2)
        OR ($5 AND p."cancelledAt" IS NULL AND p."startTime">NOW() AND (p."cityId" IS NULL OR p."cityId"=$3) AND p.services ?| $4))
        ORDER BY p."startTime" DESC LIMIT 100"#)
        .bind(uid).bind(q.business_id).bind(business.get::<Option<Uuid>,_>("cityId")).bind(services).bind(verified).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(|r| {let mut p:Value=r.get("data");p.as_object_mut().unwrap().remove("customerId");p}).collect()))
}

async fn detail(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let uid=Uuid::parse_str(&user.user_id)?;let id=Uuid::parse_str(&id)?;
    let row=sqlx::query(r#"SELECT to_jsonb(p) AS data FROM event_plans p WHERE p.id=$1 AND (p."customerId"=$2
        OR EXISTS(SELECT 1 FROM businesses b WHERE b."ownerId"=$2 AND b.type='SERVICE'
            AND (EXISTS(SELECT 1 FROM event_quotes q WHERE q."planId"=p.id AND q."businessId"=b.id)
                OR (b.status='VERIFIED' AND p."cancelledAt" IS NULL AND p."startTime">NOW() AND (p."cityId" IS NULL OR p."cityId"=b."cityId")
                    AND (p.services ? b."serviceType"::text OR p.services ?| ARRAY(SELECT jsonb_array_elements_text(b."eventServices")))))))"#)
        .bind(id).bind(uid).fetch_optional(&state.db).await?.ok_or_else(||AppError::NotFound("Event not found".into()))?;
    let mut plan:Value=row.get("data");let is_customer=plan["customerId"].as_str()==Some(user.user_id.as_str());
    let quotes=sqlx::query(r#"SELECT to_jsonb(q) || jsonb_build_object('businessName',b.name,'vendorId',b."ownerId",
        'vendorPhone',CASE WHEN q.status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED','CANCELLED') THEN b.phone ELSE NULL END,
        'cancellationRequestedByMe',q."cancellationRequestedBy"=$3,
        'expired',q."expiresAt"<=NOW() AND q.status='OFFERED') AS data
        FROM event_quotes q JOIN businesses b ON b.id=q."businessId"
        WHERE q."planId"=$1 AND ($2 OR b."ownerId"=$3) ORDER BY q."createdAt" DESC"#)
        .bind(id).bind(is_customer).bind(uid).fetch_all(&state.db).await?;
    plan["quotes"]=json!(quotes.iter().map(|r|r.get::<Value,_>("data")).collect::<Vec<_>>());
    plan["isCustomer"]=json!(is_customer);
    if !is_customer {
        let contact=sqlx::query_scalar::<_,Value>(r#"SELECT jsonb_build_object('name',u.name,'phoneNumber',u."phoneNumber")
            FROM users u JOIN event_plans p ON p."customerId"=u.id WHERE p.id=$1 AND EXISTS(
                SELECT 1 FROM event_quotes q JOIN businesses b ON b.id=q."businessId"
                WHERE q."planId"=p.id AND b."ownerId"=$2 AND q.status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED','CANCELLED'))"#)
            .bind(id).bind(uid).fetch_optional(&state.db).await?;
        plan["customerContact"]=json!(contact);
        plan.as_object_mut().unwrap().remove("customerId");
    }
    Ok(Json(plan))
}

async fn cancel_plan(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let id=Uuid::parse_str(&id)?;let mut tx=state.db.begin().await?;
    sqlx::query(r#"SELECT id FROM event_plans WHERE id=$1 AND "customerId"=$2 FOR UPDATE"#)
        .bind(id).bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::NotFound("Event not found".into()))?;
    let selected:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#)
        .bind(id).fetch_one(&mut *tx).await?;
    if selected {return Err(AppError::Conflict("Resolve each confirmed service before cancelling the event".into()));}
    sqlx::query(r#"UPDATE event_plans SET "cancelledAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#).bind(id).execute(&mut *tx).await?;
    sqlx::query(r#"UPDATE event_quotes SET status='DECLINED',"updatedAt"=NOW() WHERE "planId"=$1 AND status='OFFERED'"#).bind(id).execute(&mut *tx).await?;
    let vendors=sqlx::query_scalar::<_,Uuid>(r#"SELECT DISTINCT b."ownerId" FROM businesses b JOIN event_quotes q ON q."businessId"=b.id WHERE q."planId"=$1"#)
        .bind(id).fetch_all(&mut *tx).await?;
    for vendor in vendors {
        crate::outbox::notify(&mut tx,id,vendor,"Event enquiry cancelled","The customer cancelled the event enquiry. Any agreed refunds remain due.",json!({"type":"event_update","planId":id})).await?;
    }
    tx.commit().await?;Ok(Json(json!({"cancelled":true})))
}

fn parse_time(value:&str)->AppResult<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value).map(|d|d.with_timezone(&Utc)).map_err(|_|AppError::BadRequest("Event times must include a timezone".into()))
}
fn amount(value:f64)->AppResult<Decimal> {
    if !value.is_finite() || !(0.0..=999_999_999.0).contains(&value) {return Err(AppError::BadRequest("Invalid amount".into()));}
    Ok(Decimal::from_f64_retain(value).unwrap().round_dp(2))
}
