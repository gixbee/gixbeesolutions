use super::*;
use axum::extract::Path;
use rust_decimal::{Decimal,prelude::ToPrimitive};

pub(crate) async fn run_reconciliation(state: AppState) {
    if !razorpay_configured(&state) {
        return;
    }
    let mut interval = tokio::time::interval(std::time::Duration::from_secs(60));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        interval.tick().await;
        if let Err(error) = reconcile_recent_orders(&state).await {
            tracing::warn!(%error, "Could not claim payment reconciliation work");
        }
        if let Err(error) = expire_hiring_checkouts(&state).await {
            tracing::warn!(%error, "Could not claim expired hiring checkouts");
        }
        if let Err(error) = reconcile_pending_refunds(&state).await {
            tracing::warn!(%error, "Could not claim refund reconciliation work");
        }
    }
}

async fn reconcile_pending_refunds(state: &AppState) -> AppResult<()> {
    use futures::{stream, StreamExt};
    let ids: Vec<Uuid> = sqlx::query_scalar(
        r#"WITH candidate AS (
               SELECT id FROM payment_orders WHERE status='REFUND_PENDING' AND "razorpayRefundId" IS NOT NULL
                 AND "updatedAt" <= NOW()-INTERVAL '5 minutes'
               ORDER BY "updatedAt", id LIMIT 10 FOR UPDATE SKIP LOCKED
           )
           UPDATE payment_orders p SET "updatedAt"=NOW()
           FROM candidate c WHERE p.id=c.id RETURNING p.id"#,
    ).fetch_all(&state.db).await?;
    stream::iter(ids).for_each_concurrent(4, |id| async move {
        if let Err(error) = process_refund_required(state, &json!({"paymentOrderId": id})).await {
            tracing::warn!(%id, %error, "Refund reconciliation failed");
        }
    }).await;
    Ok(())
}

async fn reconcile_recent_orders(state: &AppState) -> AppResult<()> {
    use futures::{stream, StreamExt};
    let orders: Vec<String> = sqlx::query_scalar(
        r#"WITH candidate AS (
               SELECT p.id FROM payment_orders p
               WHERE p.status='CREATED'
                 AND p."razorpayOrderId" IS NOT NULL
                 AND p.purpose::text = ANY($1)
                 AND p."createdAt">NOW()-INTERVAL '24 hours'
                 AND COALESCE(p."reconcileAfter",p."createdAt"+INTERVAL '2 minutes')<=NOW()
                 AND NOT EXISTS (SELECT 1 FROM outbox_events e WHERE e.id=p.id AND e.type='payment.captured')
               ORDER BY COALESCE(p."reconcileAfter",p."createdAt"), p.id
               LIMIT 10 FOR UPDATE SKIP LOCKED
           )
           UPDATE payment_orders p SET "reconcileAfter"=NOW()+INTERVAL '1 hour'
           FROM candidate c WHERE p.id=c.id RETURNING p."razorpayOrderId""#,
    )
    .bind(RECOVERABLE_PAYMENT_PURPOSES)
    .fetch_all(&state.db)
    .await?;
    stream::iter(orders)
        .for_each_concurrent(4, |order_id| async move {
            if let Err(error) = reconcile_order(state, &order_id).await {
                tracing::warn!(%order_id, %error, "Payment reconciliation failed");
            }
        })
        .await;
    Ok(())
}

async fn fetch_order_payments(state: &AppState, order_id: &str) -> AppResult<Vec<Value>> {
    let response = state.http
        .get(format!("https://api.razorpay.com/v1/orders/{order_id}/payments"))
        .basic_auth(state.config.razorpay_key_id.as_deref().unwrap_or(""), state.config.razorpay_key_secret.as_deref())
        .timeout(std::time::Duration::from_secs(8))
        .send().await.map_err(|_| AppError::ServiceUnavailable("Razorpay reconciliation is unavailable".into()))?;
    if !response.status().is_success() {
        return Err(AppError::ServiceUnavailable(format!("Razorpay reconciliation returned {}", response.status())));
    }
    let body: Value = response.json().await.map_err(|_| AppError::ServiceUnavailable("Invalid Razorpay reconciliation response".into()))?;
    body["items"].as_array().cloned()
        .ok_or_else(|| AppError::ServiceUnavailable("Missing Razorpay payment list".into()))
}

async fn reconcile_order(state: &AppState, order_id: &str) -> AppResult<bool> {
    let payments = fetch_order_payments(state, order_id).await?;
    if let Some(payment) = payments.iter().find(|p| p["status"].as_str() == Some("captured")
        && p["amount_refunded"].as_i64() == Some(0)) {
        queue_captured_order(state, order_id, payment).await?;
        return Ok(true);
    }
    Ok(false)
}

async fn expire_hiring_checkouts(state: &AppState) -> AppResult<()> {
    use futures::{stream, StreamExt};
    let candidates = sqlx::query(
        r#"WITH candidate AS (
               SELECT p.id FROM payment_orders p
               WHERE p.status='CREATED' AND p.purpose='HIRING_MATCH_FEE'
                 AND p."creditReleasedAt" IS NULL AND p."createdAt"<=NOW()-INTERVAL '24 hours'
                 AND (p."reconcileAfter" IS NULL OR p."reconcileAfter"<=NOW())
                 AND NOT EXISTS(SELECT 1 FROM outbox_events e WHERE e.id=p.id AND e.type='payment.captured')
               ORDER BY p."createdAt",p.id LIMIT 10 FOR UPDATE SKIP LOCKED
           )
           UPDATE payment_orders p SET "reconcileAfter"=NOW()+INTERVAL '1 hour'
           FROM candidate c WHERE p.id=c.id
           RETURNING p.id,p."userId",p."razorpayOrderId",p.amount"#,
    ).fetch_all(&state.db).await?;
    stream::iter(candidates).for_each_concurrent(4, |row| async move {
        let id: Uuid = row.get("id");
        if let Err(error) = release_unpaid_checkout(state, id, row.get("userId"),
            row.get("razorpayOrderId"), row.get("amount")).await {
            tracing::warn!(%id, %error, "Expired hiring checkout reconciliation failed");
        }
    }).await;
    Ok(())
}

async fn release_unpaid_checkout(
    state: &AppState,
    intent: Uuid,
    employer: Uuid,
    attached_order: Option<String>,
    amount: Decimal,
) -> AppResult<()> {
    let mut provider_order = None;
    let order_id = if let Some(ref id) = attached_order {
        Some(id.clone())
    } else {
        let receipt = format!("{}_{}", razorpay_receipt_prefix(PURPOSE_HIRING_MATCH), intent.simple());
        let result: Value = state.http.get("https://api.razorpay.com/v1/orders")
            .basic_auth(state.config.razorpay_key_id.as_deref().unwrap_or(""),state.config.razorpay_key_secret.as_deref())
            .query(&[("receipt",receipt.as_str())])
            .timeout(std::time::Duration::from_secs(8))
            .send().await.and_then(reqwest::Response::error_for_status)
            .map_err(|_| AppError::ServiceUnavailable("Could not verify the hiring checkout".into()))?
            .json().await.map_err(|_| AppError::ServiceUnavailable("Invalid provider order list".into()))?;
        let items = result["items"].as_array()
            .ok_or_else(|| AppError::ServiceUnavailable("Missing provider order list".into()))?;
        provider_order = items.iter().find(|order| order["receipt"].as_str()==Some(receipt.as_str())).cloned();
        if let Some(order) = provider_order.as_ref() {
            if order["currency"].as_str()!=Some("INR")
                || order["amount"].as_i64().map(Decimal::from)!=Some(amount*Decimal::from(100)) {
                return Err(AppError::Conflict("Provider checkout amount mismatch".into()));
            }
            Some(order["id"].as_str().ok_or_else(|| AppError::ServiceUnavailable(
                "Missing provider order reference".into()))?.to_owned())
        } else {
            None
        }
    };
    if let Some(id) = order_id.as_deref() {
        let payments = fetch_order_payments(state, id).await?;
        if let Some(payment) = payments.iter().find(|payment|
            payment["status"].as_str()==Some("captured") && payment["amount_refunded"].as_i64()==Some(0)
        ) {
            if attached_order.is_none() {
                attach_captured_order(state, id, provider_order.as_ref(), payment).await?;
            }
            return queue_captured_order(state, id, payment).await;
        }
        if payments.iter().any(|payment| !matches!(payment["status"].as_str(), Some("failed" | "refunded"))) {
            return Ok(());
        }
    }

    // Use the same user lock as hiring fulfillment and new credit reservations.
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT id FROM users WHERE id=$1 FOR UPDATE")
        .bind(employer).fetch_one(&mut *tx).await?;
    // Compare the attachment against the snapshot we reconciled. A concurrent
    // attach or verified capture leaves the reservation available for fulfillment.
    sqlx::query(r#"UPDATE payment_orders p SET "creditReleasedAt"=NOW(),"updatedAt"=NOW()
        WHERE id=$1 AND "userId"=$2 AND status='CREATED' AND "creditReleasedAt" IS NULL
          AND "razorpayOrderId" IS NOT DISTINCT FROM $3::text
          AND NOT EXISTS(SELECT 1 FROM hiring_requests h WHERE h."paymentOrderId"=p.id)
          AND NOT EXISTS(SELECT 1 FROM outbox_events e WHERE e.id=p.id AND e.type='payment.captured')"#,
    ).bind(intent).bind(employer).bind(attached_order).execute(&mut *tx).await?;
    tx.commit().await?;
    Ok(())
}

fn require_recovery_admin(user: &AuthUser) -> AppResult<()> {
    require_admin(user)?;
    if user.staff_role.as_deref() != Some("SUPER_ADMIN") {
        return Err(AppError::Forbidden("Super admin access required".into()));
    }
    Ok(())
}

pub(super) async fn admin_recovery(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Value>> {
    require_recovery_admin(&user)?;
    let rows = sqlx::query(
        r#"SELECT p.id,p."razorpayOrderId",p.purpose::text AS purpose,p."createdAt",p."creditReleasedAt",
                  e.status AS "deliveryStatus",e."lastError",e.attempts
           FROM payment_orders p LEFT JOIN outbox_events e ON e.id=p.id AND e.type='payment.captured'
           WHERE p.status='CREATED' AND p.purpose::text=ANY($1)
           ORDER BY (e.status IS NOT DISTINCT FROM 'failed') DESC,p."createdAt" DESC LIMIT 100"#,
    ).bind(RECOVERABLE_PAYMENT_PURPOSES).fetch_all(&state.db).await?;
    let items: Vec<Value> = rows.iter().map(|r| json!({
        "id":r.get::<Uuid,_>("id"),
        "razorpayOrderId":r.get::<Option<String>,_>("razorpayOrderId"),
        "purpose":r.get::<String,_>("purpose"),
        "createdAt":crate::common::pg::date_json(r,"createdAt"),
        "creditReleasedAt":crate::common::pg::date_json(r,"creditReleasedAt"),
        "deliveryStatus":r.get::<Option<String>,_>("deliveryStatus"),
        "lastError":r.get::<Option<String>,_>("lastError"),
        "attempts":r.get::<Option<i32>,_>("attempts"),
    })).collect();
    Ok(Json(json!({"items":items})))
}

pub(super) async fn admin_retry(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    require_recovery_admin(&user)?;
    let row = sqlx::query(
        r#"SELECT p."razorpayOrderId",p.status::text AS status,e.status AS "deliveryStatus"
           FROM payment_orders p LEFT JOIN outbox_events e ON e.id=p.id AND e.type='payment.captured'
           WHERE p.id=$1 AND p.purpose::text=ANY($2)"#,
    ).bind(id).bind(RECOVERABLE_PAYMENT_PURPOSES).fetch_optional(&state.db).await?
        .ok_or_else(|| AppError::NotFound("Recoverable payment order not found".into()))?;
    if row.get::<String,_>("status") != "CREATED" {
        return Err(AppError::Conflict("Payment no longer needs fulfillment".into()));
    }
    match row.get::<Option<String>,_>("deliveryStatus").as_deref() {
        Some("failed" | "processed") => {
            sqlx::query(
                r#"UPDATE outbox_events e SET status='pending',attempts=0,"availableAt"=NOW(),"processedAt"=NULL
                   FROM payment_orders p WHERE e.id=$1 AND p.id=e.id AND p.status='CREATED'
                     AND e.type='payment.captured' AND e.status IN ('failed','processed')"#,
            ).bind(id).execute(&state.db).await?;
        }
        Some("pending" | "processing") => {}
        _ => {
            if !razorpay_configured(&state) {
                return Err(AppError::ServiceUnavailable("Payment gateway is unavailable".into()));
            }
            let order_id = row.get::<Option<String>,_>("razorpayOrderId")
                .ok_or_else(|| AppError::Conflict("Provider order is not attached. Resume checkout first.".into()))?;
            if !reconcile_order(&state, &order_id).await? {
                return Ok(Json(json!({"status":"no_eligible_capture"})));
            }
        }
    }
    Ok(Json(json!({"status":"queued"})))
}

pub(super) async fn pending(State(state):State<AppState>,user:AuthUser)->AppResult<Json<Vec<Value>>> {
    let rows=sqlx::query(r#"SELECT "razorpayOrderId",amount,purpose::text AS purpose,meta,"createdAt"
        FROM payment_orders WHERE "userId"=$1 AND status='CREATED' AND "razorpayOrderId" IS NOT NULL
          AND "creditReleasedAt" IS NULL
          AND purpose::text IN ('HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','PLATFORM_PLAN')
        ORDER BY "createdAt" DESC LIMIT 100"#).bind(Uuid::parse_str(&user.user_id)?).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(|r|json!({"orderId":r.get::<String,_>("razorpayOrderId"),"amount":(r.get::<Decimal,_>("amount")*Decimal::from(100)).to_i64(),
        "currency":"INR","keyId":state.config.razorpay_key_id,"purpose":r.get::<String,_>("purpose"),
        "meta":r.get::<Option<Value>,_>("meta"),"createdAt":crate::common::pg::date_json(r,"createdAt")})).collect()))
}

pub(super) async fn status(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let r=owned(&state,&user,&id).await?;
    let status: String = r.get("status");
    let status = if status=="CREATED" && r.get::<bool,_>("creditReleased") {
        "EXPIRED"
    } else {
        &status
    };
    Ok(Json(json!({"orderId":id,"status":status})))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct VerifyInput {payment_id:String}

pub(super) async fn verify(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>,Json(input):Json<VerifyInput>)->AppResult<Json<Value>> {
    let order=owned(&state,&user,&id).await?;
    let order_status: String = order.get("status");
    if matches!(order_status.as_str(), "CREDITED" | "REFUND_REQUIRED" | "REFUND_PENDING" | "REFUNDED") {
        return Ok(Json(json!({"status": order_status})));
    }
    if order_status!="CREATED" {return Err(AppError::Conflict("This order is not payable".into()));}
    if !razorpay_configured(&state) {return Err(AppError::ServiceUnavailable("Payment gateway is unavailable".into()));}
    if !input.payment_id.starts_with("pay_") || input.payment_id.len()<=4 || input.payment_id.len()>100
        || !input.payment_id[4..].chars().all(|c|c.is_ascii_alphanumeric()) {return Err(AppError::BadRequest("Invalid payment reference".into()));}
    // Trust only the provider's captured record, never a client success callback.
    let response=state.http.get(format!("https://api.razorpay.com/v1/payments/{}",input.payment_id))
        .basic_auth(state.config.razorpay_key_id.as_deref().unwrap_or(""),state.config.razorpay_key_secret.as_deref())
        .timeout(std::time::Duration::from_secs(15)).send().await
        .map_err(|_|AppError::ServiceUnavailable("Payment verification is unavailable. Your order remains saved".into()))?;
    if !response.status().is_success() {return Err(AppError::ServiceUnavailable("Payment provider has not confirmed this payment yet".into()));}
    let payment:Value=response.json().await.map_err(|_|AppError::ServiceUnavailable("Invalid payment provider response".into()))?;
    let amount:Decimal=order.get("amount");
    if payment["id"].as_str()!=Some(input.payment_id.as_str()) || payment["order_id"].as_str()!=Some(id.as_str())
        || payment["status"].as_str()!=Some("captured") || payment["currency"].as_str()!=Some("INR")
        || payment["amount"].as_i64().map(Decimal::from)!=Some(amount*Decimal::from(100)) {
        return Err(AppError::Conflict("Payment is not captured for this order and amount yet".into()));
    }
    fulfil_captured_order(&state, &id, &payment).await?;
    let status: String = sqlx::query_scalar("SELECT status::text FROM payment_orders WHERE id=$1")
        .bind(order.get::<Uuid,_>("id")).fetch_one(&state.db).await?;
    Ok(Json(json!({"status":status})))
}

async fn owned(state:&AppState,user:&AuthUser,id:&str)->AppResult<sqlx::postgres::PgRow> {
    sqlx::query(r#"SELECT id,amount,status::text AS status,purpose::text AS purpose,meta,
            "creditReleasedAt" IS NOT NULL AS "creditReleased" FROM payment_orders
        WHERE "razorpayOrderId"=$1 AND "userId"=$2 AND purpose::text IN (
            'HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','PLATFORM_PLAN',
            'PERIOD_FEE','LATE_CANCEL_COMPENSATION','RENTAL_ADVANCE','RENTAL_SETTLEMENT'
        )"#)
        .bind(id).bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&state.db).await?
        .ok_or_else(||AppError::NotFound("Payment order not found on your account".into()))
}
