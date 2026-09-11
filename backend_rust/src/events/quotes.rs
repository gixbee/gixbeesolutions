use super::*;

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct OfferInput {
    business_id:Uuid, service_type:String, amount:f64, inclusions:String, cancellation_terms:String,
}

pub(super) async fn offer(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>,Json(input):Json<OfferInput>)->AppResult<Json<Value>> {
    let price=amount(input.amount)?;
    if price<=Decimal::ZERO || input.inclusions.trim().is_empty() || input.cancellation_terms.trim().is_empty()
        || input.inclusions.len()>5000 || input.cancellation_terms.len()>5000 || !SERVICES.contains(&input.service_type.as_str()) {
        return Err(AppError::BadRequest("Include a positive total price, scope of work and cancellation terms".into()));
    }
    let uid=Uuid::parse_str(&user.user_id)?;let plan_id=Uuid::parse_str(&id)?;
    let mut tx=state.db.begin().await?;
    let business=sqlx::query(r#"SELECT "ownerId","cityId","serviceType"::text AS service,"eventServices",status::text AS status,type::text AS type
        FROM businesses WHERE id=$1 AND "ownerId"=$2 FOR UPDATE"#)
        .bind(input.business_id).bind(uid).fetch_optional(&mut *tx).await?
        .ok_or_else(||AppError::NotFound("Business not found on your account".into()))?;
    let supports=business.get::<Option<String>,_>("service").as_deref()==Some(input.service_type.as_str())
        || business.get::<Value,_>("eventServices").as_array().is_some_and(|a|a.iter().any(|v|v.as_str()==Some(input.service_type.as_str())));
    if business.get::<String,_>("status")!="VERIFIED" || business.get::<String,_>("type")!="SERVICE" || !supports {
        return Err(AppError::Forbidden("A verified business offering this service is required".into()));
    }
    let plan=sqlx::query(r#"SELECT * FROM event_plans WHERE id=$1 AND "cancelledAt" IS NULL AND "startTime">NOW() FOR UPDATE"#)
        .bind(plan_id).fetch_optional(&mut *tx).await?.ok_or_else(||AppError::Conflict("This event is no longer accepting quotes".into()))?;
    let customer:Uuid=plan.get("customerId");
    if customer==uid {return Err(AppError::BadRequest("You cannot quote for your own event".into()));}
    let city:Option<Uuid>=plan.get("cityId");
    if city.is_some() && city!=business.get::<Option<Uuid>,_>("cityId") {return Err(AppError::BadRequest("This event is outside your business city".into()));}
    if !plan.get::<Value,_>("services").as_array().is_some_and(|a|a.iter().any(|s|s.as_str()==Some(input.service_type.as_str()))) {
        return Err(AppError::BadRequest("This service was not requested".into()));
    }
    let chosen:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND "serviceType"=$2 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#)
        .bind(plan_id).bind(&input.service_type).fetch_one(&mut *tx).await?;
    if chosen {return Err(AppError::Conflict("A vendor has already been selected for this service".into()));}
    let row=sqlx::query(r#"INSERT INTO event_quotes (id,"planId","businessId","serviceType",amount,inclusions,"cancellationTerms","expiresAt")
        VALUES ($1,$2,$3,$4,$5,$6,$7,LEAST(NOW()+INTERVAL '24 hours',$8))
        ON CONFLICT ("planId","businessId","serviceType") DO UPDATE SET amount=EXCLUDED.amount,inclusions=EXCLUDED.inclusions,
            "cancellationTerms"=EXCLUDED."cancellationTerms","expiresAt"=EXCLUDED."expiresAt",status='OFFERED',"updatedAt"=NOW()
        WHERE event_quotes.status IN ('OFFERED','DECLINED','EXPIRED') RETURNING to_jsonb(event_quotes) AS data"#)
        .bind(Uuid::new_v4()).bind(plan_id).bind(input.business_id).bind(&input.service_type).bind(price)
        .bind(input.inclusions.trim()).bind(input.cancellation_terms.trim()).bind(plan.get::<DateTime<Utc>,_>("startTime"))
        .fetch_optional(&mut *tx).await?.ok_or_else(||AppError::Conflict("A confirmed quote cannot be replaced".into()))?;
    crate::outbox::notify(&mut tx,plan_id,customer,"New event quote","A business has sent pricing and terms for your event.",json!({"type":"event_quote","planId":plan_id})).await?;
    tx.commit().await?;Ok(Json(row.get("data")))
}

pub(super) async fn action(State(state):State<AppState>,user:AuthUser,Path((id,action)):Path<(String,String)>,Json(body):Json<Value>)->AppResult<Json<Value>> {
    let uid=Uuid::parse_str(&user.user_id)?;let quote_id=Uuid::parse_str(&id)?;
    let mut tx=state.db.begin().await?;
    // Serialize all calendar decisions through the business before the event/quote.
    let business=sqlx::query(r#"SELECT b.id,b."ownerId",b.status::text AS status,b."offlineDays"::jsonb AS offline
        FROM businesses b JOIN event_quotes q ON q."businessId"=b.id WHERE q.id=$1 FOR UPDATE OF b"#)
        .bind(quote_id).fetch_optional(&mut *tx).await?.ok_or_else(||AppError::NotFound("Quote not found".into()))?;
    let plan=sqlx::query(r#"SELECT p.* FROM event_plans p JOIN event_quotes q ON q."planId"=p.id WHERE q.id=$1 FOR UPDATE OF p"#)
        .bind(quote_id).fetch_one(&mut *tx).await?;
    let quote=sqlx::query("SELECT * FROM event_quotes WHERE id=$1 FOR UPDATE").bind(quote_id).fetch_one(&mut *tx).await?;
    let customer:Uuid=plan.get("customerId");let vendor:Uuid=business.get("ownerId");
    let is_customer=customer==uid;let is_vendor=vendor==uid;
    if !is_customer && !is_vendor {return Err(AppError::NotFound("Quote not found".into()));}
    let status=quote.get::<String,_>("status");let plan_id:Uuid=plan.get("id");
    // Bind customer consent to the exact quote/proposal they reviewed.
    if ["accept", "request-cancel", "accept-cancel", "reject-cancel"].contains(&action.as_str()) {
        let revision=body.get("updatedAt").and_then(Value::as_str).map(parse_time).transpose()?;
        if revision!=Some(quote.get::<DateTime<Utc>,_>("updatedAt")) {
            return Err(AppError::Conflict("This quote has changed. Refresh and review its current price and terms".into()));
        }
    }
    match action.as_str() {
        "accept" => {
            if !is_customer {return Err(AppError::Forbidden("Only the event customer can accept a quote".into()));}
            if status!="OFFERED" || quote.get::<DateTime<Utc>,_>("expiresAt")<=Utc::now()
                || plan.get::<Option<DateTime<Utc>>,_>("cancelledAt").is_some() || plan.get::<DateTime<Utc>,_>("startTime")<=Utc::now()
                || business.get::<String,_>("status")!="VERIFIED" {
                return Err(AppError::Conflict("This quote is no longer available".into()));
            }
            let start:DateTime<Utc>=plan.get("startTime");let end:DateTime<Utc>=plan.get("endTime");
            // Calendar days are civil days in the India pilot market.
            let offset=chrono::FixedOffset::east_opt(19800).unwrap();
            let first=start.with_timezone(&offset).date_naive();
            let last=(end-chrono::Duration::milliseconds(1)).with_timezone(&offset).date_naive();
            if business.get::<Option<Value>,_>("offline").and_then(|v|v.as_array().cloned()).unwrap_or_default().iter().any(|v|
                v.as_str().and_then(|s|s.get(..10)).and_then(|s|chrono::NaiveDate::parse_from_str(s,"%Y-%m-%d").ok()).is_some_and(|d|d>=first&&d<=last)) {
                return Err(AppError::Conflict("The business is unavailable on an event day".into()));
            }
            let conflict:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
                WHERE q."businessId"=$1 AND q.status IN ('CONFIRMED','CANCEL_REQUESTED') AND p."startTime"<$3 AND p."endTime">$2
                    AND q."planId"<>$4)"#)
                .bind(business.get::<Uuid,_>("id")).bind(start).bind(end).bind(plan_id).fetch_one(&mut *tx).await?;
            if conflict {return Err(AppError::Conflict("The business has another event at this time".into()));}
            let selected:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND "serviceType"=$2 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#)
                .bind(plan_id).bind(quote.get::<String,_>("serviceType")).fetch_one(&mut *tx).await?;
            if selected {return Err(AppError::Conflict("A vendor has already been selected for this service".into()));}
            sqlx::query(r#"UPDATE event_quotes SET status='CONFIRMED',"acceptedAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#)
                .bind(quote_id).execute(&mut *tx).await?;
            sqlx::query(r#"UPDATE event_quotes SET status='DECLINED',"updatedAt"=NOW() WHERE "planId"=$1 AND "serviceType"=$2 AND id<>$3 AND status='OFFERED'"#)
                .bind(plan_id).bind(quote.get::<String,_>("serviceType")).bind(quote_id).execute(&mut *tx).await?;
        },
        "decline" => {
            if status!="OFFERED" {return Err(AppError::Conflict("Only an open quote can be declined or withdrawn".into()));}
            sqlx::query("UPDATE event_quotes SET status='DECLINED',\"updatedAt\"=NOW() WHERE id=$1").bind(quote_id).execute(&mut *tx).await?;
        },
        "payment" | "complete" => {
            if status!="CONFIRMED" {return Err(AppError::Conflict("This action requires a confirmed booking".into()));}
            if action=="complete" && plan.get::<DateTime<Utc>,_>("startTime")>Utc::now() {return Err(AppError::Conflict("The event has not started".into()));}
            let column=match (action.as_str(),is_customer) {("payment",true)=>"customerPaidAt",("payment",false)=>"vendorReceivedAt",(_,true)=>"customerCompletedAt",(_,false)=>"vendorCompletedAt"};
            sqlx::query(&format!(r#"UPDATE event_quotes SET "{column}"=COALESCE("{column}",NOW()),"updatedAt"=NOW() WHERE id=$1"#))
                .bind(quote_id).execute(&mut *tx).await?;
            sqlx::query(r#"UPDATE event_quotes SET status='COMPLETED' WHERE id=$1 AND "customerPaidAt" IS NOT NULL AND "vendorReceivedAt" IS NOT NULL
                AND "customerCompletedAt" IS NOT NULL AND "vendorCompletedAt" IS NOT NULL"#).bind(quote_id).execute(&mut *tx).await?;
        },
        "request-cancel" => {
            if status!="CONFIRMED" {return Err(AppError::Conflict("Only a confirmed service can request cancellation".into()));}
            let reason=body.get("reason").and_then(Value::as_str).unwrap_or("").trim();
            let refund=amount(body.get("refundAmount").and_then(Value::as_f64).unwrap_or(0.0))?;
            if reason.is_empty() || reason.len()>2000 || refund>quote.get::<Decimal,_>("amount") {return Err(AppError::BadRequest("Provide a cancellation reason and a refund within the quote total".into()));}
            sqlx::query(r#"UPDATE event_quotes SET status='CANCEL_REQUESTED',"cancellationRequestedBy"=$2,"cancellationReason"=$3,
                "cancellationRefund"=$4,"updatedAt"=NOW() WHERE id=$1"#).bind(quote_id).bind(uid).bind(reason).bind(refund).execute(&mut *tx).await?;
        },
        "accept-cancel" | "reject-cancel" => {
            if status!="CANCEL_REQUESTED" || quote.get::<Option<Uuid>,_>("cancellationRequestedBy")==Some(uid) {
                return Err(AppError::Conflict("The other participant must respond to cancellation".into()));
            }
            sqlx::query(r#"UPDATE event_quotes SET status=$2,"updatedAt"=NOW() WHERE id=$1"#)
                .bind(quote_id).bind(if action=="accept-cancel" {"CANCELLED"} else {"CONFIRMED"}).execute(&mut *tx).await?;
        },
        "refund" => {
            if status!="CANCELLED" || quote.get::<Decimal,_>("cancellationRefund")<=Decimal::ZERO {return Err(AppError::Conflict("No cancellation refund is due".into()));}
            let column=if is_customer {"customerRefundReceivedAt"} else {"vendorRefundSentAt"};
            sqlx::query(&format!(r#"UPDATE event_quotes SET "{column}"=COALESCE("{column}",NOW()),"updatedAt"=NOW() WHERE id=$1"#))
                .bind(quote_id).execute(&mut *tx).await?;
        },
        _=>return Err(AppError::BadRequest("Unknown event action".into())),
    }
    crate::outbox::notify(&mut tx,plan_id,if is_customer {vendor} else {customer},"Event booking update",
        "A participant updated your event booking. Open the event to review its status.",json!({"type":"event_update","planId":plan_id})).await?;
    tx.commit().await?;
    super::detail(State(state),user,Path(plan_id.to_string())).await
}
