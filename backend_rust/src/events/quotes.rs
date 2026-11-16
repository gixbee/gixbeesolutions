use super::*;
use crate::halls::availability::{
    acquire_hall_scope_locks, availability_check, lock_business_rows, release_holds_for_quote,
    Interval,
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct OfferInput {
    business_id: Uuid,
    service_type: String,
    amount: f64,
    inclusions: String,
    cancellation_terms: String,
    #[serde(default)]
    hall_enquiry_id: Option<Uuid>,
    #[serde(default)]
    hall_id: Option<Uuid>,
    #[serde(default)]
    interval_start: Option<String>,
    #[serde(default)]
    interval_end: Option<String>,
}

pub(super) async fn offer(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(mut input): Json<OfferInput>,
) -> AppResult<Json<Value>> {
    let price = amount(input.amount)?;
    if price <= Decimal::ZERO
        || input.inclusions.trim().is_empty()
        || input.cancellation_terms.trim().is_empty()
        || input.inclusions.len() > 5000
        || input.cancellation_terms.len() > 5000
        || !SERVICES.contains(&input.service_type.as_str())
    {
        return Err(AppError::BadRequest(
            "Include a positive total price, scope of work and cancellation terms".into(),
        ));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    let plan_id = Uuid::parse_str(&id)?;
    let mut tx = state.db.begin().await?;
    // Event, then business, then (for a hall offer) venue and halls, then quote rows.
    let plan = sqlx::query(r#"SELECT * FROM event_plans WHERE id=$1 FOR UPDATE"#)
        .bind(plan_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::Conflict("This event is no longer accepting quotes".into()))?;
    if plan.get::<Option<DateTime<Utc>>, _>("cancelledAt").is_some()
        || plan.get::<DateTime<Utc>, _>("startTime") <= Utc::now()
    {
        return Err(AppError::Conflict(
            "This event is no longer accepting quotes".into(),
        ));
    }
    if plan.get::<Option<Uuid>, _>("targetBusinessId").is_some_and(|id| id != input.business_id) {
        return Err(AppError::NotFound("This enquiry belongs to another provider".into()));
    }
    if let Err(err) = lock_business_rows(&mut *tx, &[input.business_id]).await {
        return Err(match err {
            AppError::NotFound(_) => {
                AppError::NotFound("Business not found on your account".into())
            }
            other => other,
        });
    }
    let business = sqlx::query(
        r#"SELECT "ownerId","cityId","serviceType"::text AS service,"eventServices",status::text AS status,type::text AS type
        FROM businesses WHERE id=$1"#,
    )
    .bind(input.business_id)
    .fetch_one(&mut *tx)
    .await?;
    if business.get::<Uuid, _>("ownerId") != uid {
        return Err(AppError::NotFound(
            "Business not found on your account".into(),
        ));
    }
    let supports = business.get::<Option<String>, _>("service").as_deref()
        == Some(input.service_type.as_str())
        || business
            .get::<Value, _>("eventServices")
            .as_array()
            .is_some_and(|a| a.iter().any(|v| v.as_str() == Some(input.service_type.as_str())));
    if business.get::<String, _>("status") != "VERIFIED"
        || business.get::<String, _>("type") != "SERVICE"
        || !supports
    {
        return Err(AppError::Forbidden(
            "A verified business offering this service is required".into(),
        ));
    }
    let customer: Uuid = plan.get("customerId");
    if customer == uid {
        return Err(AppError::BadRequest(
            "You cannot quote for your own event".into(),
        ));
    }
    let city: Option<Uuid> = plan.get("cityId");
    if plan.get::<Option<Uuid>, _>("targetBusinessId").is_none()
        && city.is_some() && city != business.get::<Option<Uuid>, _>("cityId") {
        return Err(AppError::BadRequest(
            "This event is outside your business city".into(),
        ));
    }
    if !plan
        .get::<Value, _>("services")
        .as_array()
        .is_some_and(|a| a.iter().any(|s| s.as_str() == Some(input.service_type.as_str())))
    {
        return Err(AppError::BadRequest(
            "This service was not requested".into(),
        ));
    }
    let chosen: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND "serviceType"=$2 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#,
    )
    .bind(plan_id)
    .bind(&input.service_type)
    .fetch_one(&mut *tx)
    .await?;
    if chosen {
        return Err(AppError::Conflict(
            "A vendor has already been selected for this service".into(),
        ));
    }

    let is_hall = if input.service_type == "HALL" {
        let assignment = sqlx::query(
            r#"SELECT id, "assignedHallId" FROM hall_enquiries
               WHERE "eventPlanId"=$1 AND "businessId"=$2"#,
        )
        .bind(plan_id)
        .bind(input.business_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(assignment) = assignment {
            let enquiry_id: Uuid = assignment.get("id");
            let hall_id: Option<Uuid> = assignment.get("assignedHallId");
            if input.hall_enquiry_id.is_some_and(|id| id != enquiry_id)
                || (input.hall_id.is_some() && input.hall_id != hall_id)
            {
                return Err(AppError::Conflict("The hall assignment has changed".into()));
            }
            input.hall_enquiry_id = Some(enquiry_id);
            input.hall_id = Some(hall_id.ok_or_else(|| {
                AppError::Conflict("Assign a hall before sending a quote".into())
            })?);
            true
        } else if input.hall_enquiry_id.is_some() || input.hall_id.is_some() {
            return Err(AppError::NotFound("Hall enquiry not found for this event".into()));
        } else {
            false
        }
    } else {
        false
    };

    let row = if is_hall {
        offer_hall_revision(&mut tx, &input, plan_id, &plan, price, uid).await?
    } else {
        // Legacy non-hall (and HALL without enquiry): upsert on open statuses.
        sqlx::query(
            r#"INSERT INTO event_quotes (id,"planId","businessId","serviceType",amount,inclusions,"cancellationTerms","expiresAt",revision)
        VALUES ($1,$2,$3,$4,$5,$6,$7,LEAST(NOW()+INTERVAL '24 hours',$8),1)
        ON CONFLICT ("planId","businessId","serviceType",revision) DO UPDATE SET amount=EXCLUDED.amount,inclusions=EXCLUDED.inclusions,
            "cancellationTerms"=EXCLUDED."cancellationTerms","expiresAt"=EXCLUDED."expiresAt",status='OFFERED',"updatedAt"=NOW()
        WHERE event_quotes.status IN ('OFFERED','DECLINED','EXPIRED','SUPERSEDED') RETURNING to_jsonb(event_quotes) AS data"#,
        )
        .bind(Uuid::new_v4())
        .bind(plan_id)
        .bind(input.business_id)
        .bind(&input.service_type)
        .bind(price)
        .bind(input.inclusions.trim())
        .bind(input.cancellation_terms.trim())
        .bind(plan.get::<DateTime<Utc>, _>("startTime"))
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::Conflict("A confirmed quote cannot be replaced".into()))?
    };

    crate::outbox::notify(
        &mut tx,
        plan_id,
        customer,
        "New event quote",
        "A business has sent pricing and terms for your event.",
        json!({"type":"event_quote","planId":plan_id,"quoteId": row.get::<Value,_>("data")["id"]}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(row.get("data")))
}

async fn offer_hall_revision(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    input: &OfferInput,
    plan_id: Uuid,
    plan: &sqlx::postgres::PgRow,
    price: Decimal,
    uid: Uuid,
) -> AppResult<sqlx::postgres::PgRow> {
    let enquiry_id = input.hall_enquiry_id.ok_or_else(|| {
        AppError::BadRequest("hallEnquiryId is required when offering a hall quote".into())
    })?;
    let hall_id = input.hall_id.ok_or_else(|| {
        AppError::BadRequest("hallId is required when offering a hall quote".into())
    })?;

    // offer() already locked the event and the business. Venue and halls next,
    // then the enquiry and quote rows.
    acquire_hall_scope_locks(&mut **tx, input.business_id, Some(&[hall_id])).await?;

    let enq = sqlx::query(
        r#"SELECT * FROM hall_enquiries
           WHERE id=$1 AND "businessId"=$2 AND "eventPlanId"=$3 FOR UPDATE"#,
    )
    .bind(enquiry_id)
    .bind(input.business_id)
    .bind(plan_id)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall enquiry not found".into()))?;
    let estatus: String = enq.get("status");
    if !["ASSIGNED", "QUOTE_OFFERED"].contains(&estatus.as_str()) {
        return Err(AppError::Conflict(
            "Assign a hall before sending a quote".into(),
        ));
    }
    if enq.get::<Option<Uuid>, _>("assignedHallId") != Some(hall_id) {
        return Err(AppError::BadRequest(
            "hallId must match the enquiry assignment".into(),
        ));
    }

    let start = if let Some(ref s) = input.interval_start {
        DateTime::parse_from_rfc3339(s)
            .map(|d| d.with_timezone(&Utc))
            .map_err(|_| AppError::BadRequest("intervalStart must be RFC3339".into()))?
    } else {
        enq.get::<Option<DateTime<Utc>>, _>("proposedStartAt")
            .unwrap_or_else(|| plan.get("startTime"))
    };
    let end = if let Some(ref s) = input.interval_end {
        DateTime::parse_from_rfc3339(s)
            .map(|d| d.with_timezone(&Utc))
            .map_err(|_| AppError::BadRequest("intervalEnd must be RFC3339".into()))?
    } else {
        enq.get::<Option<DateTime<Utc>>, _>("proposedEndAt")
            .unwrap_or_else(|| plan.get("endTime"))
    };
    let interval = Interval::new(start, end)?;
    if plan.get::<Option<Uuid>, _>("targetBusinessId").is_some()
        && (start != plan.get::<DateTime<Utc>, _>("startTime")
            || end != plan.get::<DateTime<Utc>, _>("endTime"))
    {
        return Err(AppError::Conflict("Use the hall slot requested by the customer".into()));
    }
    let package = crate::halls::load_hall_package(&mut **tx, hall_id).await?;
    crate::halls::ensure_package_window(package.as_ref(), start)?;

    // Supersede any current OFFERED revision for this vendor/service.
    let prior: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM event_quotes
           WHERE "planId"=$1 AND "businessId"=$2 AND "serviceType"=$3 AND status='OFFERED'
           FOR UPDATE"#,
    )
    .bind(plan_id)
    .bind(input.business_id)
    .bind(&input.service_type)
    .fetch_optional(&mut **tx)
    .await?;
    if let Some(pid) = prior {
        sqlx::query(
            r#"UPDATE event_quotes SET status='SUPERSEDED',"supersedeReason"='REOFFER',"updatedAt"=NOW()
               WHERE id=$1"#,
        )
        .bind(pid)
        .execute(&mut **tx)
        .await?;
        release_holds_for_quote(&mut **tx, pid).await?;
    }

    // Exclude assignment hold for this enquiry when checking.
    let assign_hold: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM hall_reservations
           WHERE "enquiryId"=$1 AND status='HELD' AND "expiresAt">NOW()
           ORDER BY "createdAt" DESC LIMIT 1"#,
    )
    .bind(enquiry_id)
    .fetch_optional(&mut **tx)
    .await?;
    availability_check(
        &mut **tx,
        input.business_id,
        Some(hall_id),
        interval,
        assign_hold,
    )
    .await?;

    let next_rev: i32 = sqlx::query_scalar(
        r#"SELECT COALESCE(MAX(revision),0)+1 FROM event_quotes
           WHERE "planId"=$1 AND "businessId"=$2 AND "serviceType"=$3"#,
    )
    .bind(plan_id)
    .bind(input.business_id)
    .bind(&input.service_type)
    .fetch_one(&mut **tx)
    .await?;

    let quote_id = Uuid::new_v4();
    let expires = plan
        .get::<DateTime<Utc>, _>("startTime")
        .min(Utc::now() + chrono::Duration::hours(24));

    let row = sqlx::query(
        r#"INSERT INTO event_quotes
           (id,"planId","businessId","serviceType",amount,inclusions,"cancellationTerms","expiresAt",
            revision,"supersedesQuoteId","hallEnquiryId","hallId","intervalStart","intervalEnd")
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
           RETURNING to_jsonb(event_quotes) AS data"#,
    )
    .bind(quote_id)
    .bind(plan_id)
    .bind(input.business_id)
    .bind(&input.service_type)
    .bind(price)
    .bind(input.inclusions.trim())
    .bind(input.cancellation_terms.trim())
    .bind(expires)
    .bind(next_rev)
    .bind(prior)
    .bind(enquiry_id)
    .bind(hall_id)
    .bind(start)
    .bind(end)
    .fetch_one(&mut **tx)
    .await?;

    // Convert assignment hold → quote hold (or insert quote hold).
    if let Some(hid) = assign_hold {
        sqlx::query(
            r#"UPDATE hall_reservations SET "quoteId"=$2, "expiresAt"=$3,
               "startAt"=$4, "endAt"=$5, "updatedAt"=NOW()
               WHERE id=$1"#,
        )
        .bind(hid)
        .bind(quote_id)
        .bind(expires)
        .bind(start)
        .bind(end)
        .execute(&mut **tx)
        .await?;
    } else {
        sqlx::query(
            r#"INSERT INTO hall_reservations
               (id,"businessId","hallId","enquiryId","quoteId","startAt","endAt",status,"expiresAt")
               VALUES ($1,$2,$3,$4,$5,$6,$7,'HELD',$8)"#,
        )
        .bind(Uuid::new_v4())
        .bind(input.business_id)
        .bind(hall_id)
        .bind(enquiry_id)
        .bind(quote_id)
        .bind(start)
        .bind(end)
        .bind(expires)
        .execute(&mut **tx)
        .await?;
    }

    // Terms snapshot from hall package if present.
    if let Some(pkg_id) = sqlx::query_scalar::<_, Option<Uuid>>(
        r#"SELECT "packageRevisionId" FROM business_halls WHERE id=$1"#,
    )
    .bind(hall_id)
    .fetch_one(&mut **tx)
    .await?
    {
        if let Some(pkg) = sqlx::query_scalar::<_, Option<Value>>(
            r#"SELECT package FROM business_hall_package_revisions WHERE id=$1"#,
        )
        .bind(pkg_id)
        .fetch_one(&mut **tx)
        .await?
        {
            let basis = pkg
                .get("deductionBasis")
                .and_then(|v| v.as_str())
                .unwrap_or("ADVANCE")
                .to_string();
            sqlx::query(
                r#"INSERT INTO hall_booking_terms_snapshot
                   (id,"quoteId","quoteRevision","packageRevisionId","hallId","deductionBasis",terms)
                   VALUES ($1,$2,$3,$4,$5,$6,$7)"#,
            )
            .bind(Uuid::new_v4())
            .bind(quote_id)
            .bind(next_rev)
            .bind(pkg_id)
            .bind(hall_id)
            .bind(basis)
            .bind(pkg)
            .execute(&mut **tx)
            .await?;
        }
    }

    sqlx::query(
        r#"UPDATE hall_enquiries SET status='QUOTE_OFFERED',"activeQuoteId"=$2,"updatedAt"=NOW()
           WHERE id=$1"#,
    )
    .bind(enquiry_id)
    .bind(quote_id)
    .execute(&mut **tx)
    .await?;

    crate::halls::audit::write_audit(
        &mut **tx,
        input.business_id,
        Some(hall_id),
        "quote",
        &quote_id.to_string(),
        "offer",
        uid,
        json!({"revision": next_rev}),
    )
    .await?;
    Ok(row)
}

pub(super) async fn action(
    State(state): State<AppState>,
    user: AuthUser,
    Path((id, action)): Path<(String, String)>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let quote_id = Uuid::parse_str(&id)?;
    let mut tx = state.db.begin().await?;
    // Unlocked read only to find the rows to lock. State is checked again after the locks.
    let located = sqlx::query(r#"SELECT "planId","businessId" FROM event_quotes WHERE id=$1"#)
        .bind(quote_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("Quote not found".into()))?;
    let plan_id: Uuid = located.get("planId");
    let business_id: Uuid = located.get("businessId");
    // Event, then business, then venue and halls when this is a hall quote, then the quote row.
    let plan = sqlx::query(r#"SELECT * FROM event_plans WHERE id=$1 FOR UPDATE"#)
        .bind(plan_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("Quote not found".into()))?;
    if let Err(err) = lock_business_rows(&mut *tx, &[business_id]).await {
        return Err(match err {
            AppError::NotFound(_) => AppError::NotFound("Quote not found".into()),
            other => other,
        });
    }
    let business = sqlx::query(
        r#"SELECT id,"ownerId",status::text AS status,"offlineDays"::jsonb AS offline
           FROM businesses WHERE id=$1"#,
    )
    .bind(business_id)
    .fetch_one(&mut *tx)
    .await?;
    let preview = sqlx::query(
        r#"SELECT "hallId","serviceType"::text AS "serviceType" FROM event_quotes WHERE id=$1"#,
    )
    .bind(quote_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Quote not found".into()))?;
    let preview_hall: Option<Uuid> = preview.try_get("hallId").ok().flatten();
    let preview_service: String = preview.get("serviceType");
    if preview_hall.is_some() || preview_service == "HALL" {
        let lock = preview_hall.map(|hall| vec![hall]);
        acquire_hall_scope_locks(&mut *tx, business_id, lock.as_deref()).await?;
    }
    let quote = sqlx::query("SELECT * FROM event_quotes WHERE id=$1 FOR UPDATE")
        .bind(quote_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or_else(|| AppError::NotFound("Quote not found".into()))?;
    if quote.get::<Uuid, _>("planId") != plan_id || quote.get::<Uuid, _>("businessId") != business_id
    {
        return Err(AppError::Conflict(
            "This quote has changed. Refresh and review its current price and terms".into(),
        ));
    }
    let customer: Uuid = plan.get("customerId");
    let vendor: Uuid = business.get("ownerId");
    let is_customer = customer == uid;
    let is_vendor = vendor == uid;
    if !is_customer && !is_vendor {
        return Err(AppError::NotFound("Quote not found".into()));
    }
    let status = quote.get::<String, _>("status");
    let hall_id: Option<Uuid> = quote.try_get("hallId").ok().flatten();
    let service_type: String = quote.get("serviceType");
    if (hall_id.is_some() || service_type == "HALL")
        && hall_id != preview_hall
    {
        // The event lock blocks other quote writers, so this is a stale preview.
        return Err(AppError::Conflict(
            "This quote has changed. Refresh and review its current price and terms".into(),
        ));
    }

    if ["accept", "request-cancel", "accept-cancel", "reject-cancel"].contains(&action.as_str()) {
        let revision = body
            .get("updatedAt")
            .and_then(Value::as_str)
            .map(parse_time)
            .transpose()?;
        if revision != Some(quote.get::<DateTime<Utc>, _>("updatedAt")) {
            return Err(AppError::Conflict(
                "This quote has changed. Refresh and review its current price and terms".into(),
            ));
        }
    }

    match action.as_str() {
        "accept" => {
            if !is_customer {
                return Err(AppError::Forbidden(
                    "Only the event customer can accept a quote".into(),
                ));
            }
            if status != "OFFERED"
                || quote.get::<DateTime<Utc>, _>("expiresAt") <= Utc::now()
                || plan.get::<Option<DateTime<Utc>>, _>("cancelledAt").is_some()
                || plan.get::<DateTime<Utc>, _>("startTime") <= Utc::now()
                || business.get::<String, _>("status") != "VERIFIED"
            {
                return Err(AppError::Conflict(
                    "This quote is no longer available".into(),
                ));
            }
            let start: DateTime<Utc> = quote
                .try_get::<Option<DateTime<Utc>>, _>("intervalStart")
                .ok()
                .flatten()
                .unwrap_or_else(|| plan.get("startTime"));
            let end: DateTime<Utc> = quote
                .try_get::<Option<DateTime<Utc>>, _>("intervalEnd")
                .ok()
                .flatten()
                .unwrap_or_else(|| plan.get("endTime"));
            let interval = Interval::new(start, end)?;
            let biz_id: Uuid = business.get("id");
            if let Some(hall) = hall_id {
                let package = crate::halls::load_hall_package(&mut *tx, hall).await?;
                crate::halls::ensure_package_window(package.as_ref(), start)?;
            }

            let hold_id: Option<Uuid> = sqlx::query_scalar(
                r#"SELECT id FROM hall_reservations
                   WHERE "quoteId"=$1 AND status='HELD' AND "expiresAt">NOW() LIMIT 1"#,
            )
            .bind(quote_id)
            .fetch_optional(&mut *tx)
            .await?;

            if hall_id.is_some() || service_type == "HALL" {
                // Venue and halls were locked before this quote row.
                availability_check(&mut *tx, biz_id, hall_id, interval, hold_id).await?;
            } else {
                // Legacy path (non-hall).
                super::calendar::check_overlap(&mut tx, biz_id, start, end).await?;
                super::catalogues::check_daily_limit(
                    &mut tx, biz_id, &service_type, plan_id, start, end,
                ).await?;
                let offset = chrono::FixedOffset::east_opt(19800).unwrap();
                let first = start.with_timezone(&offset).date_naive();
                let last = (end - chrono::Duration::milliseconds(1))
                    .with_timezone(&offset)
                    .date_naive();
                if business
                    .get::<Option<Value>, _>("offline")
                    .and_then(|v| v.as_array().cloned())
                    .unwrap_or_default()
                    .iter()
                    .any(|v| {
                        v.as_str()
                            .and_then(|s| s.get(..10))
                            .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                            .is_some_and(|d| d >= first && d <= last)
                    })
                {
                    return Err(AppError::Conflict(
                        "The business is unavailable on an event day".into(),
                    ));
                }
                let conflict: bool = sqlx::query_scalar(
                    r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
                WHERE q."businessId"=$1 AND q.status IN ('CONFIRMED','CANCEL_REQUESTED') AND p."startTime"<$3 AND p."endTime">$2
                    AND q."planId"<>$4)"#,
                )
                .bind(biz_id)
                .bind(start)
                .bind(end)
                .bind(plan_id)
                .fetch_one(&mut *tx)
                .await?;
                if conflict {
                    return Err(AppError::Conflict(
                        "The business has another event at this time".into(),
                    ));
                }
            }

            let selected: bool = sqlx::query_scalar(
                r#"SELECT EXISTS(SELECT 1 FROM event_quotes WHERE "planId"=$1 AND "serviceType"=$2 AND status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED'))"#,
            )
            .bind(plan_id)
            .bind(&service_type)
            .fetch_one(&mut *tx)
            .await?;
            if selected {
                return Err(AppError::Conflict(
                    "A vendor has already been selected for this service".into(),
                ));
            }
            sqlx::query(
                r#"UPDATE event_quotes SET status='CONFIRMED',"acceptedAt"=NOW(),"updatedAt"=NOW() WHERE id=$1"#,
            )
            .bind(quote_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                r#"UPDATE event_quotes SET status='DECLINED',"updatedAt"=NOW()
                   WHERE "planId"=$1 AND "serviceType"=$2 AND id<>$3 AND status='OFFERED'"#,
            )
            .bind(plan_id)
            .bind(&service_type)
            .bind(quote_id)
            .execute(&mut *tx)
            .await?;

            if let Some(hid) = hold_id {
                sqlx::query(
                    r#"UPDATE hall_reservations SET status='CONFIRMED',"expiresAt"=NULL,"updatedAt"=NOW()
                       WHERE id=$1"#,
                )
                .bind(hid)
                .execute(&mut *tx)
                .await?;
            } else if let Some(h) = hall_id {
                sqlx::query(
                    r#"INSERT INTO hall_reservations
                       (id,"businessId","hallId","enquiryId","quoteId","startAt","endAt",status)
                       VALUES ($1,$2,$3,$4,$5,$6,$7,'CONFIRMED')"#,
                )
                .bind(Uuid::new_v4())
                .bind(biz_id)
                .bind(h)
                .bind(quote.try_get::<Option<Uuid>, _>("hallEnquiryId").ok().flatten())
                .bind(quote_id)
                .bind(start)
                .bind(end)
                .execute(&mut *tx)
                .await?;
            }
            if let Some(eid) = quote.try_get::<Option<Uuid>, _>("hallEnquiryId").ok().flatten() {
                sqlx::query(
                    r#"UPDATE hall_enquiries SET status='CUSTOMER_ACCEPTED',"updatedAt"=NOW() WHERE id=$1"#,
                )
                .bind(eid)
                .execute(&mut *tx)
                .await?;
            }
            // Creates the photography payment/deliverable schedule or hall
            // advance deadline from the immutable selected catalogue and
            // package terms. The same DB transaction confirms the quote.
            super::milestones::seed_at_acceptance(
                &mut tx,
                quote_id,
                &service_type,
                &plan,
                quote.get::<Decimal, _>("amount"),
            )
            .await?;
        }
        "decline" => {
            if status != "OFFERED" {
                return Err(AppError::Conflict(
                    "Only an open quote can be declined or withdrawn".into(),
                ));
            }
            sqlx::query(
                "UPDATE event_quotes SET status='DECLINED',\"updatedAt\"=NOW() WHERE id=$1",
            )
            .bind(quote_id)
            .execute(&mut *tx)
            .await?;
            release_holds_for_quote(&mut *tx, quote_id).await?;
            if let Some(eid) = quote.try_get::<Option<Uuid>, _>("hallEnquiryId").ok().flatten() {
                sqlx::query(
                    r#"UPDATE hall_enquiries SET status='QUOTE_DECLINED',"updatedAt"=NOW() WHERE id=$1"#,
                )
                .bind(eid)
                .execute(&mut *tx)
                .await?;
            }
        }
        "payment" | "complete" => {
            if status != "CONFIRMED" {
                return Err(AppError::Conflict(
                    "This action requires a confirmed booking".into(),
                ));
            }
            // Old bookings without milestone rows retain their previous
            // acknowledgement behavior. New schedules must be completed
            // before the full-payment / service-complete shortcuts are used.
            let outstanding: i64 = sqlx::query_scalar(
                r#"SELECT COUNT(*) FROM event_quote_milestones
                   WHERE "quoteId"=$1 AND kind=$2 AND "completedAt" IS NULL"#,
            )
            .bind(quote_id)
            .bind(if action == "payment" { "PAYMENT" } else { "DELIVERY" })
            .fetch_one(&mut *tx)
            .await?;
            if outstanding > 0 {
                return Err(AppError::Conflict(
                    "Confirm each agreed milestone with both parties first".into(),
                ));
            }
            if action == "complete" && plan.get::<DateTime<Utc>, _>("startTime") > Utc::now() {
                return Err(AppError::Conflict("The event has not started".into()));
            }
            let column = match (action.as_str(), is_customer) {
                ("payment", true) => "customerPaidAt",
                ("payment", false) => "vendorReceivedAt",
                (_, true) => "customerCompletedAt",
                (_, false) => "vendorCompletedAt",
            };
            sqlx::query(&format!(
                r#"UPDATE event_quotes SET "{column}"=COALESCE("{column}",NOW()),"updatedAt"=NOW() WHERE id=$1"#
            ))
            .bind(quote_id)
            .execute(&mut *tx)
            .await?;
            // Hall-linked: COMPLETED without payment timestamps.
            // Legacy / non-hall: require all four acknowledgements.
            if hall_id.is_some() && service_type == "HALL" {
                sqlx::query(
                    r#"UPDATE event_quotes SET status='COMPLETED' WHERE id=$1
                       AND "customerCompletedAt" IS NOT NULL AND "vendorCompletedAt" IS NOT NULL"#,
                )
                .bind(quote_id)
                .execute(&mut *tx)
                .await?;
            } else {
                sqlx::query(
                    r#"UPDATE event_quotes SET status='COMPLETED' WHERE id=$1 AND "customerPaidAt" IS NOT NULL AND "vendorReceivedAt" IS NOT NULL
                AND "customerCompletedAt" IS NOT NULL AND "vendorCompletedAt" IS NOT NULL"#,
                )
                .bind(quote_id)
                .execute(&mut *tx)
                .await?;
            }
        }
        "request-cancel" => {
            if status != "CONFIRMED" {
                return Err(AppError::Conflict(
                    "Only a confirmed service can request cancellation".into(),
                ));
            }
            let reason = body
                .get("reason")
                .and_then(Value::as_str)
                .unwrap_or("")
                .trim();
            let refund = amount(
                body.get("refundAmount")
                    .and_then(Value::as_f64)
                    .unwrap_or(0.0),
            )?;
            if reason.is_empty() || reason.len() > 2000 || refund > quote.get::<Decimal, _>("amount")
            {
                return Err(AppError::BadRequest(
                    "Provide a cancellation reason and a refund within the quote total".into(),
                ));
            }
            sqlx::query(
                r#"UPDATE event_quotes SET status='CANCEL_REQUESTED',"cancellationRequestedBy"=$2,"cancellationReason"=$3,
                "cancellationRefund"=$4,"updatedAt"=NOW() WHERE id=$1"#,
            )
            .bind(quote_id)
            .bind(uid)
            .bind(reason)
            .bind(refund)
            .execute(&mut *tx)
            .await?;
        }
        "accept-cancel" | "reject-cancel" => {
            if status != "CANCEL_REQUESTED"
                || quote.get::<Option<Uuid>, _>("cancellationRequestedBy") == Some(uid)
            {
                return Err(AppError::Conflict(
                    "The other participant must respond to cancellation".into(),
                ));
            }
            let next = if action == "accept-cancel" {
                "CANCELLED"
            } else {
                "CONFIRMED"
            };
            sqlx::query(r#"UPDATE event_quotes SET status=$2,"updatedAt"=NOW() WHERE id=$1"#)
                .bind(quote_id)
                .bind(next)
                .execute(&mut *tx)
                .await?;
            if next == "CANCELLED" {
                // Cancel-first MVP: release CONFIRMED reservation.
                sqlx::query(
                    r#"UPDATE hall_reservations SET status='RELEASED',"releasedAt"=NOW(),"updatedAt"=NOW()
                       WHERE "quoteId"=$1 AND status='CONFIRMED'"#,
                )
                .bind(quote_id)
                .execute(&mut *tx)
                .await?;
                if let Some(eid) =
                    quote.try_get::<Option<Uuid>, _>("hallEnquiryId").ok().flatten()
                {
                    // Re-offer only while the parent event is still active.
                    // A whole-event cancel leaves the enquiry CANCELLED.
                    sqlx::query(
                        r#"UPDATE hall_enquiries e
                           SET status='ASSIGNED', "activeQuoteId"=NULL, "updatedAt"=NOW()
                           FROM event_plans p
                           WHERE e.id=$1 AND e."eventPlanId"=p.id
                             AND p."cancelledAt" IS NULL
                             AND e."assignedHallId" IS NOT NULL
                             AND e.status NOT IN ('CANCELLED','OWNER_DECLINED','QUOTE_DECLINED','QUOTE_EXPIRED')"#,
                    )
                    .bind(eid)
                    .execute(&mut *tx)
                    .await?;
                }
            }
        }
        "refund" => {
            if status != "CANCELLED"
                || quote.get::<Decimal, _>("cancellationRefund") <= Decimal::ZERO
            {
                return Err(AppError::Conflict(
                    "No cancellation refund is due".into(),
                ));
            }
            let column = if is_customer {
                "customerRefundReceivedAt"
            } else {
                "vendorRefundSentAt"
            };
            sqlx::query(&format!(
                r#"UPDATE event_quotes SET "{column}"=COALESCE("{column}",NOW()),"updatedAt"=NOW() WHERE id=$1"#
            ))
            .bind(quote_id)
            .execute(&mut *tx)
            .await?;
        }
        _ => return Err(AppError::BadRequest("Unknown event action".into())),
    }
    crate::outbox::notify(
        &mut tx,
        plan_id,
        if is_customer { vendor } else { customer },
        "Event booking update",
        "A participant updated your event booking. Open the event to review its status.",
        json!({"type":"event_update","planId":plan_id}),
    )
    .await?;
    tx.commit().await?;
    super::detail(State(state), user, Path(plan_id.to_string())).await
}
