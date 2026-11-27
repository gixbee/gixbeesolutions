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
    }
}

async fn reconcile_recent_orders(state: &AppState) -> AppResult<()> {
    use futures::{stream, StreamExt};
    let orders: Vec<String> = sqlx::query_scalar(
        r#"WITH candidate AS (
               SELECT p.id FROM payment_orders p
               WHERE p.status='CREATED'
                 AND p.purpose::text IN ('PERIOD_FEE','LATE_CANCEL_COMPENSATION','RENTAL_ADVANCE','RENTAL_SETTLEMENT')
                 AND p."createdAt">NOW()-INTERVAL '24 hours'
                 AND COALESCE(p."reconcileAfter",p."createdAt"+INTERVAL '2 minutes')<=NOW()
                 AND NOT EXISTS (SELECT 1 FROM outbox_events e WHERE e.id=p.id AND e.type='payment.captured')
               ORDER BY COALESCE(p."reconcileAfter",p."createdAt"), p.id
               LIMIT 10 FOR UPDATE SKIP LOCKED
           )
           UPDATE payment_orders p SET "reconcileAfter"=NOW()+INTERVAL '1 hour'
           FROM candidate c WHERE p.id=c.id RETURNING p."razorpayOrderId""#,
    )
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

async fn reconcile_order(state: &AppState, order_id: &str) -> AppResult<()> {
    let response = state.http
        .get(format!("https://api.razorpay.com/v1/orders/{order_id}/payments"))
        .basic_auth(state.config.razorpay_key_id.as_deref().unwrap_or(""), state.config.razorpay_key_secret.as_deref())
        .timeout(std::time::Duration::from_secs(8))
        .send().await.map_err(|_| AppError::ServiceUnavailable("Razorpay reconciliation is unavailable".into()))?;
    if !response.status().is_success() {
        return Err(AppError::ServiceUnavailable(format!("Razorpay reconciliation returned {}", response.status())));
    }
    let body: Value = response.json().await.map_err(|_| AppError::ServiceUnavailable("Invalid Razorpay reconciliation response".into()))?;
    let payments = body["items"].as_array().ok_or_else(|| AppError::ServiceUnavailable("Missing Razorpay payment list".into()))?;
    if let Some(payment) = payments.iter().find(|p| p["status"].as_str() == Some("captured")
        && p["amount_refunded"].as_i64() == Some(0)) {
        apply_legacy_payment(state, order_id, payment).await?;
    }
    Ok(())
}

pub(super) async fn pending(State(state):State<AppState>,user:AuthUser)->AppResult<Json<Vec<Value>>> {
    let rows=sqlx::query(r#"SELECT "razorpayOrderId",amount,purpose::text AS purpose,meta,"createdAt"
        FROM payment_orders WHERE "userId"=$1 AND status='CREATED' AND purpose::text IN ('HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','PLATFORM_PLAN')
        ORDER BY "createdAt" DESC LIMIT 100"#).bind(Uuid::parse_str(&user.user_id)?).fetch_all(&state.db).await?;
    Ok(Json(rows.iter().map(|r|json!({"orderId":r.get::<String,_>("razorpayOrderId"),"amount":(r.get::<Decimal,_>("amount")*Decimal::from(100)).to_i64(),
        "currency":"INR","keyId":state.config.razorpay_key_id,"purpose":r.get::<String,_>("purpose"),
        "meta":r.get::<Option<Value>,_>("meta"),"createdAt":crate::common::pg::date_json(r,"createdAt")})).collect()))
}

pub(super) async fn status(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>)->AppResult<Json<Value>> {
    let r=owned(&state,&user,&id).await?;
    Ok(Json(json!({"orderId":id,"status":r.get::<String,_>("status")})))
}

#[derive(Deserialize)]
#[serde(rename_all="camelCase")]
pub(super) struct VerifyInput {payment_id:String}

pub(super) async fn verify(State(state):State<AppState>,user:AuthUser,Path(id):Path<String>,Json(input):Json<VerifyInput>)->AppResult<Json<Value>> {
    let order=owned(&state,&user,&id).await?;
    if order.get::<String,_>("status")=="CREDITED" {return Ok(Json(json!({"status":"CREDITED"})));}
    if order.get::<String,_>("status")!="CREATED" {return Err(AppError::Conflict("This order is not payable".into()));}
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
    let meta:Option<Value>=order.get("meta");let purpose:String=order.get("purpose");let order_id:Uuid=order.get("id");
    if matches!(purpose.as_str(), PURPOSE_PERIOD_FEE | PURPOSE_LATE_CANCEL | PURPOSE_RENTAL_ADVANCE | PURPOSE_RENTAL_SETTLEMENT) {
        apply_legacy_payment(&state, &id, &payment).await?;
        return Ok(Json(json!({"status":"CREDITED"})));
    }
    fulfil_order(&state,&id,&user.user_id,amount.to_i32().unwrap_or(0),&purpose,meta.as_ref(),order_id,Some(&input.payment_id)).await?;
    sqlx::query(r#"UPDATE payment_orders SET status='CREDITED',"razorpayPaymentId"=$2,"updatedAt"=NOW() WHERE id=$1 AND status='CREATED'"#)
        .bind(order_id).bind(&input.payment_id).execute(&state.db).await?;
    Ok(Json(json!({"status":"CREDITED"})))
}

async fn owned(state:&AppState,user:&AuthUser,id:&str)->AppResult<sqlx::postgres::PgRow> {
    sqlx::query(r#"SELECT id,amount,status::text AS status,purpose::text AS purpose,meta FROM payment_orders
        WHERE "razorpayOrderId"=$1 AND "userId"=$2 AND purpose::text IN (
            'HIRING_MATCH_FEE','EXTRA_JOB_TYPE_FEE','PLATFORM_PLAN',
            'PERIOD_FEE','LATE_CANCEL_COMPENSATION','RENTAL_ADVANCE','RENTAL_SETTLEMENT'
        )"#)
        .bind(id).bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&state.db).await?
        .ok_or_else(||AppError::NotFound("Payment order not found on your account".into()))
}
