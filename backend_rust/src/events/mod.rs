use axum::{extract::{Path, Query, State}, routing::{get, post}, Json, Router};
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;
use crate::{error::{AppError, AppResult}, middleware::auth::AuthUser, state::AppState};

mod quotes;
mod catalogues;
mod calendar;
mod milestones;
mod commerce_common;
mod deliveries;
mod settlement;
mod payment_evidence;
pub const SERVICES: [&str;8] = ["HALL","CATERING","DECORATION","PHOTOGRAPHY","DJ","MAKEUP","MEHENDI","INVITATIONS"];

/// Photography, catering, and other non-hall services mark a full IST day
/// unavailable on `event_vendor_calendar`. Halls use `hall_calendar_blocks`.
pub async fn set_vendor_unavailable_day(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    business: Uuid,
    actor: Uuid,
    day: chrono::NaiveDate,
    add: bool,
) -> AppResult<()> {
    calendar::set_unavailable_day(&mut *tx, business, actor, day, add).await
}

pub fn routes() -> Router<AppState> {
    Router::new().route("/",get(my_plans).post(create_plan))
        .route("/vendor/inbox",get(vendor_inbox))
        .route("/quotes/{id}/{action}",post(quotes::action))
        .route("/{id}",get(detail))
        .route("/{id}/quotes",post(quotes::offer))
        .route("/{id}/cancel",post(cancel_plan))
        .merge(catalogues::routes())
        .merge(calendar::routes())
        .merge(milestones::routes())
        .merge(deliveries::routes())
        .merge(settlement::routes())
        .merge(payment_evidence::routes())
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
struct PlanInput {
    event_type:String, start_time:String, end_time:String, guest_count:i32,
    location:String, city_id:Option<Uuid>, services:Vec<String>, #[serde(default)] notes:String,
    target_business_id: Option<Uuid>,
    service_request: Option<Value>,
    client_request_id: Option<Uuid>,
}

/// Only bounded, non-priced preferences are accepted. The server still
/// recalculates estimates from stored catalogue items / hall slots.
fn validate_customization(service: &str, raw: &Value) -> AppResult<Value> {
    let fields: &[&str] = match service {
        "CATERING" => &["servingStyle", "dietaryNeeds", "menuChanges"],
        "PHOTOGRAPHY" => &["functions", "coverage", "team", "deliverables", "extras"],
        "DECORATION" => &["theme", "colors", "setup", "extras"],
        _ => return Err(AppError::BadRequest(
            "Customization is supported for catering, photography and decoration".into()
        )),
    };
    let source = raw.as_object().ok_or_else(|| {
        AppError::BadRequest("Customization must be an object".into())
    })?;
    if source.len() > fields.len() || raw.to_string().len() > 5000 {
        return Err(AppError::BadRequest("Customization is too large".into()));
    }
    let mut result = serde_json::Map::new();
    for (key, value) in source {
        if !fields.contains(&key.as_str()) {
            return Err(AppError::BadRequest(
                "Only supported service customization fields are allowed".into()
            ));
        }
        if key == "functions" {
            let items = value.as_array().ok_or_else(|| {
                AppError::BadRequest("Functions must be a list".into())
            })?;
            if items.len() > 8 || items.iter().any(|v| {
                v.as_str().is_none_or(|s| s.trim().is_empty() || s.len() > 90)
            }) {
                return Err(AppError::BadRequest("Choose up to eight valid functions".into()));
            }
            let distinct = items.iter().filter_map(Value::as_str)
                .map(str::trim).collect::<std::collections::HashSet<_>>();
            if distinct.len() != items.len() {
                return Err(AppError::BadRequest("Choose distinct functions".into()));
            }
            result.insert(key.clone(), json!(items));
        } else {
            let text = value.as_str().ok_or_else(|| {
                AppError::BadRequest("Customization fields must be text".into())
            })?.trim();
            if text.len() > 900 {
                return Err(AppError::BadRequest("Customization field is too long".into()));
            }
            result.insert(key.clone(), json!(text));
        }
    }
    Ok(Value::Object(result))
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
    if let Some(request_id) = input.client_request_id {
        let existing: Option<Uuid> = sqlx::query_scalar(
            r#"SELECT id FROM event_plans WHERE "customerId"=$1 AND "clientRequestId"=$2"#,
        ).bind(uid).bind(request_id).fetch_optional(&state.db).await?;
        if let Some(existing) = existing {
            return detail(State(state), user, Path(existing.to_string())).await;
        }
    }
    let mut tx=state.db.begin().await?;
    let active_city:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM cities WHERE id=$1 AND "isActive"=true)"#)
        .bind(input.city_id).fetch_one(&mut *tx).await?;
    if !active_city {return Err(AppError::BadRequest("Select an active serviceable city for the event".into()));}
    let service_request = if let Some(business) = input.target_business_id {
        let request = input.service_request.as_ref().ok_or_else(|| {
            AppError::BadRequest("Choose a service from the provider".into())
        })?;
        if input.services.len() != 1 {
            return Err(AppError::BadRequest("A request to a named provider must have one service".into()));
        }
        let service = &input.services[0];
        let provider_name: Option<String> = sqlx::query_scalar(
            r#"SELECT name FROM businesses WHERE id=$1 AND "ownerId"<>$2
                 AND type='SERVICE' AND status='VERIFIED'
                 AND ("cityId"=$3::uuid OR EXISTS (
                   SELECT 1 FROM event_service_catalogues c WHERE c."businessId"=businesses.id
                     AND c."serviceType"=$4 AND (
                       c.catalogue->'serviceCityIds' ? ($3::uuid)::text
                       OR EXISTS (
                         SELECT 1 FROM cities searched
                         WHERE searched.id = $3
                           AND EXISTS (
                             SELECT 1
                             FROM jsonb_array_elements_text(
                               COALESCE(c.catalogue->'serviceAreaIds', '[]'::jsonb)) picked(id)
                             JOIN hiring_locations area
                               ON area.id = picked.id AND area."isActive"
                             WHERE (area.kind = 'STATE'
                                    AND lower(btrim(area.name)) = lower(btrim(searched.state)))
                                OR (area.kind = 'DISTRICT'
                                    AND lower(btrim(area."stateName")) = lower(btrim(searched.state))
                                    AND lower(btrim(area.name)) = lower(btrim(searched.name)))
                           )
                       )
                     )))
                 AND ("serviceType"::text=$4 OR "eventServices" ? $4) FOR UPDATE"#,
        ).bind(business).bind(uid).bind(input.city_id).bind(service)
            .fetch_optional(&mut *tx).await?;
        let provider_name = provider_name.ok_or_else(|| AppError::NotFound("Provider unavailable in this city".into()))?;
        let mut selection = if service == "HALL" {
            crate::halls::requested_slot(&mut tx, business, input.guest_count,
                crate::halls::availability::Interval::new(start,end)?, request).await?
        } else {
            catalogues::selection(&mut tx, business, service, input.guest_count, start, request).await?
        };
        if request["expectedEstimate"].as_i64() != selection["estimate"].as_i64() {
            return Err(AppError::Conflict("The price changed. Return to the listing and review the latest price.".into()));
        }
        selection["providerName"] = json!(provider_name);
        if let Some(extra) = request.get("customization") {
            selection["customization"] = validate_customization(service, extra)?;
        }
        Some(selection)
    } else {
        if input.service_request.is_some() {
            return Err(AppError::BadRequest("Choose a provider for this request".into()));
        }
        None
    };
    let created: Option<Uuid> = sqlx::query_scalar(r#"INSERT INTO event_plans (id,"customerId","eventType","startTime","endTime","guestCount",location,"cityId",services,notes,"targetBusinessId","serviceRequest","clientRequestId")
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
        ON CONFLICT ("customerId","clientRequestId") DO NOTHING RETURNING id"#)
        .bind(id).bind(uid).bind(input.event_type.trim()).bind(start).bind(end).bind(input.guest_count)
        .bind(input.location.trim()).bind(input.city_id).bind(json!(input.services)).bind(input.notes.trim())
        .bind(input.target_business_id).bind(service_request).bind(input.client_request_id)
        .fetch_optional(&mut *tx).await?;
    if created.is_none() {
        let previous: Uuid = sqlx::query_scalar(
            r#"SELECT id FROM event_plans WHERE "customerId"=$1 AND "clientRequestId"=$2"#,
        ).bind(uid).bind(input.client_request_id).fetch_one(&mut *tx).await?;
        tx.commit().await?;
        return detail(State(state), user, Path(previous.to_string())).await;
    }
    let vendors=sqlx::query(r#"SELECT DISTINCT "ownerId" FROM businesses WHERE type='SERVICE' AND status='VERIFIED'
        AND "ownerId"<>$1 AND ($2::uuid IS NULL OR "cityId"=$2 OR id=$4)
        AND ("serviceType"::text=ANY($3) OR "eventServices" ?| $3)
        AND ($4::uuid IS NULL OR id=$4) LIMIT 200"#)
        .bind(uid).bind(input.city_id).bind(&input.services).bind(input.target_business_id).fetch_all(&mut *tx).await?;
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
        input.target_business_id,
    )
    .await?;
    tx.commit().await?;
    detail(State(state),user,Path(id.to_string())).await
}

async fn my_plans(State(state):State<AppState>,user:AuthUser)->AppResult<Json<Vec<Value>>> {
    let rows=sqlx::query(r#"SELECT to_jsonb(p) || jsonb_build_object('confirmedServices',
        (SELECT count(*) FROM event_quotes q WHERE q."planId"=p.id AND q.status IN ('CONFIRMED','COMPLETED')),
        'completedServices',(SELECT count(*) FROM event_quotes q WHERE q."planId"=p.id AND q.status='COMPLETED'),
        'offeredServices',(SELECT count(*) FROM event_quotes q WHERE q."planId"=p.id
            AND q.status='OFFERED' AND q."expiresAt" > NOW())) AS data
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
    let rows=sqlx::query(r#"SELECT to_jsonb(p) || jsonb_build_object('bookingStatus',
        (SELECT q.status::text FROM event_quotes q WHERE q."planId"=p.id AND q."businessId"=$2
         AND q.status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED')
         ORDER BY q."updatedAt" DESC LIMIT 1)) AS data FROM event_plans p WHERE p."customerId"<>$1
        AND (p."targetBusinessId" IS NULL OR p."targetBusinessId"=$2)
        AND (EXISTS(SELECT 1 FROM event_quotes q WHERE q."planId"=p.id AND q."businessId"=$2)
        OR ($5 AND p."cancelledAt" IS NULL AND p."startTime">NOW()
          AND (p."cityId" IS NULL OR p."cityId"=$3 OR p."targetBusinessId"=$2) AND p.services ?| $4))
        ORDER BY p."startTime" DESC LIMIT 100"#)
        .bind(uid).bind(q.business_id).bind(business.get::<Option<Uuid>,_>("cityId")).bind(services).bind(verified).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(|r| {let mut p:Value=r.get("data");p.as_object_mut().unwrap().remove("customerId");p}).collect()))
}

async fn detail(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let uid=Uuid::parse_str(&user.user_id)?;let id=Uuid::parse_str(&id)?;
    let row=sqlx::query(r#"SELECT to_jsonb(p) AS data FROM event_plans p WHERE p.id=$1 AND (p."customerId"=$2
        OR EXISTS(SELECT 1 FROM businesses b WHERE b."ownerId"=$2 AND b.type='SERVICE'
            AND (p."targetBusinessId" IS NULL OR p."targetBusinessId"=b.id)
            AND (EXISTS(SELECT 1 FROM event_quotes q WHERE q."planId"=p.id AND q."businessId"=b.id)
                OR (b.status='VERIFIED' AND p."cancelledAt" IS NULL AND p."startTime">NOW()
                    AND (p."cityId" IS NULL OR p."cityId"=b."cityId" OR p."targetBusinessId"=b.id)
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
        if plan["services"].as_array().is_some_and(|services| {
            services.iter().any(|service| service.as_str() == Some("HALL"))
        }) {
            let enquiries = sqlx::query_scalar::<_, Value>(
                r#"SELECT jsonb_build_object('id', e.id, 'businessId', e."businessId",
                           'assignedHallId', e."assignedHallId", 'hallName', h.name, 'status', e.status,
                           'proposedStartAt', e."proposedStartAt", 'proposedEndAt', e."proposedEndAt")
                   FROM hall_enquiries e JOIN businesses b ON b.id=e."businessId"
                   LEFT JOIN business_halls h ON h.id=e."assignedHallId"
                   WHERE e."eventPlanId"=$1 AND b."ownerId"=$2"#,
            )
            .bind(id)
            .bind(uid)
            .fetch_all(&state.db)
            .await?;
            plan["hallEnquiries"] = json!(enquiries);
        }
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
    let id=Uuid::parse_str(&id)?;
    let uid=Uuid::parse_str(&user.user_id)?;
    let mut tx=state.db.begin().await?;
    // event_plans, then businesses in id order, then each venue and its halls, then children.
    let already:Option<DateTime<Utc>>=sqlx::query_scalar::<_, Option<DateTime<Utc>>>(
        r#"SELECT "cancelledAt" FROM event_plans WHERE id=$1 AND "customerId"=$2 FOR UPDATE"#,
    )
        .bind(id).bind(uid).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::NotFound("Event not found".into()))?;
    let first_cancel=already.is_none();
    if first_cancel {
        let selected:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#)
            .bind(id).fetch_one(&mut *tx).await?;
        if selected {return Err(AppError::Conflict("Resolve each confirmed service before cancelling the event".into()));}
        sqlx::query(r#"UPDATE event_plans SET "cancelledAt"=NOW(),"updatedAt"=NOW() WHERE id=$1 AND "cancelledAt" IS NULL"#)
            .bind(id).execute(&mut *tx).await?;
    }
    let business_ids:Vec<Uuid>=sqlx::query_scalar(
        r#"SELECT "businessId" FROM (
             SELECT "businessId" FROM hall_enquiries WHERE "eventPlanId"=$1
             UNION
             SELECT r."businessId" FROM hall_reservations r
             WHERE r.status='HELD' AND (
               r."enquiryId" IN (SELECT id FROM hall_enquiries WHERE "eventPlanId"=$1)
               OR r."quoteId" IN (SELECT id FROM event_quotes WHERE "planId"=$1)
             )
           ) s ORDER BY 1"#,
    ).bind(id).fetch_all(&mut *tx).await?;
    crate::halls::availability::lock_business_rows(&mut *tx, &business_ids).await?;
    for business_id in &business_ids {
        crate::halls::availability::acquire_hall_scope_locks(&mut *tx, *business_id, None).await?;
    }
    sqlx::query(r#"UPDATE event_quotes SET status='DECLINED',"updatedAt"=NOW() WHERE "planId"=$1 AND status='OFFERED'"#)
        .bind(id).execute(&mut *tx).await?;
    let enquiries=sqlx::query(
        r#"UPDATE hall_enquiries
           SET status='CANCELLED', "activeQuoteId"=NULL, "updatedAt"=NOW()
           WHERE "eventPlanId"=$1
             AND status NOT IN ('OWNER_DECLINED','QUOTE_DECLINED','QUOTE_EXPIRED','CANCELLED')
           RETURNING id, "businessId", "assignedHallId""#,
    ).bind(id).fetch_all(&mut *tx).await?;
    let released=crate::halls::availability::release_held_for_plan(&mut *tx, id).await?;
    for enquiry in &enquiries {
        let enquiry_id:Uuid=enquiry.get("id");
        let business_id:Uuid=enquiry.get("businessId");
        let hall_id:Option<Uuid>=enquiry.try_get("assignedHallId").ok().flatten();
        crate::halls::audit::write_audit(
            &mut *tx, business_id, hall_id, "enquiry", &enquiry_id.to_string(), "cancel", uid,
            json!({"planId": id, "reason": "event_cancelled"}),
        ).await?;
        crate::halls::audit::bump_hall_caches(&mut tx, business_id, hall_id).await?;
    }
    for reservation in &released {
        let reservation_id:Uuid=reservation.get("id");
        let business_id:Uuid=reservation.get("businessId");
        let hall_id:Option<Uuid>=reservation.try_get("hallId").ok().flatten();
        crate::halls::audit::write_audit(
            &mut *tx, business_id, hall_id, "reservation", &reservation_id.to_string(), "release", uid,
            json!({"planId": id, "reason": "event_cancelled"}),
        ).await?;
        crate::halls::audit::bump_hall_caches(&mut tx, business_id, hall_id).await?;
    }
    if first_cancel {
        let vendors=sqlx::query_scalar::<_,Uuid>(r#"SELECT DISTINCT b."ownerId" FROM businesses b JOIN event_quotes q ON q."businessId"=b.id WHERE q."planId"=$1"#)
            .bind(id).fetch_all(&mut *tx).await?;
        for vendor in vendors {
            crate::outbox::notify(&mut tx,id,vendor,"Event enquiry cancelled","The customer cancelled the event enquiry. Any agreed refunds remain due.",json!({"type":"event_update","planId":id})).await?;
        }
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

#[cfg(test)]
mod customization_tests {
    use super::*;

    #[test]
    fn accepts_bounded_catering_preferences() {
        let v = validate_customization("CATERING", &json!({
            "servingStyle": "Buffet Service",
            "dietaryNeeds": "Vegetarian",
            "menuChanges": "Less spicy"
        })).unwrap();
        assert_eq!(v["dietaryNeeds"], "Vegetarian");
    }

    #[test]
    fn accepts_decoration_preference_without_changing_price() {
        let selection = validate_customization("DECORATION", &json!({
            "theme":"Traditional Kerala", "colors":"White and gold",
            "setup":"Indoor stage", "extras":"Fresh flowers"
        })).unwrap();
        assert_eq!(selection["theme"], "Traditional Kerala");
        assert!(validate_customization("DECORATION", &json!({
            "theme":"Traditional Kerala", "expectedEstimate":1
        })).is_err());
        assert!(validate_customization("DECORATION", &json!({
            "discountPct":99
        })).is_err());
    }

    #[test]
    fn rejects_untrusted_pricing_override() {
        assert!(validate_customization("PHOTOGRAPHY", &json!({
            "extras": "Drone", "expectedEstimate": 1
        })).is_err());
    }

    #[test]
    fn rejects_duplicate_functions() {
        assert!(validate_customization("PHOTOGRAPHY", &json!({
            "functions": ["Reception", "Reception"]
        })).is_err());
    }
}
