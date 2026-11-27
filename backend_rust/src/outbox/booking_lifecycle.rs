use serde_json::{json, Value};
use tracing::error;

use crate::redis::OPTIONAL_REDIS_TIMEOUT;
use crate::state::AppState;
use crate::workers;

pub async fn handle(state: &AppState, event_type: &str, payload: &Value) -> Result<(), String> {
    match event_type {
        "booking.gps_progress" => crate::bookings::progress::dispatch_gps_progress(state,payload).await.map_err(|e|e.to_string()),
        "hiring.refund" => Ok(()),
        "payment.captured" => {
            let order_id = str_field(payload, "orderId")?;
            let payment = payload.get("payment").ok_or("Missing captured payment")?;
            crate::payments::apply_legacy_payment(state, &order_id, payment)
                .await
                .map_err(|error| error.to_string())
        }
        "marketplace.notify" => {
            let uid = str_field(payload, "userId")?;
            // An account without a registered device still sees the durable offer/status in the app.
            let token: Option<String> = sqlx::query_scalar(r#"SELECT "fcmToken" FROM users WHERE id=$1"#)
                .bind(uuid::Uuid::parse_str(&uid).map_err(|e|e.to_string())?)
                .fetch_optional(&state.db).await.map_err(|e|e.to_string())?.flatten();
            if token.as_deref().unwrap_or("").is_empty() { return Ok(()); }
            let title = str_field(payload,"title")?;
            let body = str_field(payload,"body")?;
            let mut data = payload.get("data").and_then(Value::as_object).map(|o|o.iter()
                .filter_map(|(k,v)|v.as_str().map(|v|(k.as_str(),v))).collect::<Vec<_>>()).unwrap_or_default();
            if let Some(event_id) = payload.get("eventId").and_then(Value::as_str) {
                data.push(("eventId", event_id));
            }
            if state.fcm.send_to_user(state,&uid,&title,&body,Some(&data)).await { Ok(()) }
            else { Err("Marketplace push delivery failed".into()) }
        },
        "booking.broadcast_created" => on_broadcast_created(state, payload).await,
        "booking.accepted" => on_accepted(state, payload).await,
        "booking.cancelled" => on_cancelled(state, payload).await,
        "booking.completed" => on_completed(state, payload).await,
        "booking.payment_confirmed" => on_payment_confirmed(state, payload).await,
        other => {
            error!("unknown outbox type {} — marking processed", other);
            Ok(())
        }
    }
}

async fn on_broadcast_created(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    let customer_id = str_field(p, "customerId")?;
    let attempt = p.get("attempt").and_then(|v| v.as_u64()).unwrap_or(1) as u32;
    let arrival_otp = str_field(p, "arrivalOtp")?;
    let batch_ids: Vec<uuid::Uuid> = p
        .get("notifiedWorkerIds")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter_map(|id| uuid::Uuid::parse_str(id).ok())
        .collect();
    let notified_ok: Vec<String> = sqlx::query_scalar(
        r#"SELECT o.worker_id::text FROM booking_offer_recipients o
           JOIN bookings b ON b.id=o.booking_id
           WHERE o.booking_id=$1 AND o.worker_id=ANY($2) AND o.dismissed_at IS NULL
             AND o.expires_at>NOW() AND b.status='REQUESTED' AND b."operatorId" IS NULL"#,
    )
    .bind(uuid::Uuid::parse_str(&booking_id).map_err(|e| e.to_string())?)
    .bind(batch_ids)
    .fetch_all(&state.db)
    .await
    .map_err(|e| e.to_string())?;

    if notified_ok.is_empty() {
        return Ok(());
    }

    if attempt == 1 {
        cache_and_emit(
            state,
            &booking_id,
            json!({
                "status": "REQUESTED",
                "operatorName": null,
                "operatorId": null,
                "customerId": customer_id,
                "arrivalOtp": arrival_otp,
            }),
        )
        .await;
    }

    let notified_at = p
        .get("notifiedAt")
        .and_then(|v| v.as_str())
        .map(String::from)
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());
    let socket_payload = json!({
        "id": booking_id,
        "skill": p.get("skill").cloned().unwrap_or(Value::Null),
        "serviceLocation": p.get("serviceLocation").cloned().unwrap_or(Value::Null),
        "serviceLat": p.get("serviceLat").cloned().unwrap_or(Value::Null),
        "serviceLng": p.get("serviceLng").cloned().unwrap_or(Value::Null),
        "amount": p.get("amount").cloned().unwrap_or(json!(0)),
        "type": "INSTANT",
        "customer_name": p.get("customerName").and_then(|v| v.as_str()).unwrap_or("Customer"),
        "description": p.get("description").cloned().unwrap_or(Value::Null),
        "preferredLanguages": p.get("preferredLanguages").cloned().unwrap_or(json!([])),
        "createdAt": p.get("createdAt").and_then(|v| v.as_str()).unwrap_or(notified_at.as_str()),
        "notifiedAt": notified_at,
        "attempt": attempt,
    });

    let _ = tokio::time::timeout(
        OPTIONAL_REDIS_TIMEOUT,
        futures::future::join_all(notified_ok.iter().map(|wid| {
            state.realtime.emit_to_user(wid, "new_booking_request", &socket_payload)
        })),
    )
    .await;

    let customer_name = p
        .get("customerName")
        .and_then(|v| v.as_str())
        .unwrap_or("A customer");
    let skill = p.get("skill").and_then(|v| v.as_str()).unwrap_or("help");
    let amount = p
        .get("amount")
        .and_then(|v| v.as_f64().or_else(|| v.as_i64().map(|i| i as f64)))
        .unwrap_or(0.0);
    let service_location = p
        .get("serviceLocation")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let service_lat = p
        .get("serviceLat")
        .map(|v| v.to_string())
        .unwrap_or_default();
    let service_lng = p
        .get("serviceLng")
        .map(|v| v.to_string())
        .unwrap_or_default();
    let amount_str = amount.to_string();
    let created_at = p
        .get("createdAt")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let attempt_str = attempt.to_string();
    let description = p
        .get("description")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let preferred_languages = p
        .get("preferredLanguages")
        .map(|v| v.to_string())
        .unwrap_or_else(|| "[]".to_string());
    let fcm_data = [
        ("eventId", p.get("eventId").and_then(Value::as_str).unwrap_or(&booking_id)),
        ("type", "new_booking"),
        ("bookingId", booking_id.as_str()),
        ("skill", skill),
        ("serviceLocation", service_location.as_str()),
        ("serviceLat", service_lat.as_str()),
        ("serviceLng", service_lng.as_str()),
        ("amount", amount_str.as_str()),
        ("createdAt", created_at.as_str()),
        ("notifiedAt", notified_at.as_str()),
        ("attempt", attempt_str.as_str()),
        ("customer_name", customer_name),
        ("description", description.as_str()),
        ("preferredLanguages", preferred_languages.as_str()),
    ];
    state
        .fcm
        .send_to_users(
            state,
            &notified_ok,
            "New Job Request",
            &format!("{} needs {} help nearby · ₹{}/hr", customer_name, skill, amount),
            Some(&fcm_data),
        )
        .await;

    Ok(())
}

async fn on_accepted(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    let worker_id = str_field(p, "workerId")?;
    let customer_id = p.get("customerId").and_then(|v| v.as_str());
    let operator_name = p.get("operatorName").and_then(|v| v.as_str());
    let arrival_otp = p.get("arrivalOtp").and_then(|v| v.as_str());

    workers::set_worker_status(state, &worker_id, "busy").await;

    cache_and_emit(
        state,
        &booking_id,
        json!({
            "status": "ACCEPTED",
            "operatorName": operator_name,
            "operatorId": worker_id,
            "customerId": customer_id,
            "arrivalOtp": arrival_otp,
        }),
    )
    .await;

    let cancelled_customer_ids: Vec<String> = p
        .get("cancelledCustomerIds")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    if !cancelled_customer_ids.is_empty() {
        state
            .fcm
            .send_to_users(
                state,
                &cancelled_customer_ids,
                "Booking Cancelled",
                "The worker accepted another job. Please try booking again.",
                Some(&[("type", "booking_cancelled")]),
            )
            .await;
    }

    let cancelled_booking_ids: Vec<String> = p
        .get("cancelledBookingIds")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    for cancelled_id in &cancelled_booking_ids {
        cache_and_emit(
            state,
            cancelled_id,
            json!({
                "status": "CANCELLED",
                "operatorName": null,
                "operatorId": worker_id,
                "customerId": null,
            }),
        )
        .await;
    }


    if let Some(cid) = customer_id {
        let accept_payload = json!({
            "id": booking_id,
            "bookingId": booking_id,
            "status": "ACCEPTED",
            "operatorName": operator_name.unwrap_or(""),
            "operatorId": worker_id,
            "arrivalOtp": arrival_otp,
        });
        state
            .realtime
            .emit_to_user(cid, "booking_accepted", &accept_payload)
            .await;
        state
            .fcm
            .send_to_user(
                state,
                cid,
                "Request Accepted!",
                &format!("{} is on the way.", operator_name.unwrap_or("Your worker")),
                Some(&[
                    ("type", "booking_accepted"),
                    ("bookingId", booking_id.as_str()),
                    ("operatorName", operator_name.unwrap_or("")),
                    ("operatorId", worker_id.as_str()),
                ]),
            )
            .await;
    }

    Ok(())
}

async fn on_cancelled(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    let source = p.get("source").and_then(|v| v.as_str()).unwrap_or("system");
    let operator_id = p.get("operatorId").and_then(|v| v.as_str());
    let customer_id = p.get("customerId").and_then(|v| v.as_str());
    let operator_name = p.get("operatorName").and_then(|v| v.as_str());

    if let Some(op) = operator_id {
        if source == "customer" || source == "WORKER_NO_PROGRESS" {
            let body = if source == "WORKER_NO_PROGRESS" {
                "The customer cancelled — GPS showed you were not heading to the job."
            } else {
                "A customer cancelled their booking."
            };
            state
                .fcm
                .send_to_user(
                    state,
                    op,
                    "Booking cancelled",
                    body,
                    Some(&[
                        ("type", "booking_cancelled"),
                        ("bookingId", booking_id.as_str()),
                    ]),
                )
                .await;
        }
    }

    let notified = get_notified_worker_ids(state, &booking_id).await;

    let extras: Vec<String> = p
        .get("notifyWorkerIds")
        .and_then(|v| v.as_array())
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default();
    let others: Vec<String> = notified
        .into_iter()
        .chain(extras)
        .filter(|wid| operator_id.map(|op| op != wid).unwrap_or(true))
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();

    if source == "customer" && !others.is_empty() {
        state
            .fcm
            .send_to_users(
                state,
                &others,
                "Booking cancelled",
                "A customer cancelled their request.",
                Some(&[
                    ("type", "booking_cancelled"),
                    ("bookingId", booking_id.as_str()),
                ]),
            )
            .await;
    }

    if source == "timeout" {
        if let Some(cid) = customer_id {
            state
                .fcm
                .send_to_user(
                    state,
                    cid,
                    "No Workers Available",
                    "No worker accepted your request within the time limit. Please try again.",
                    Some(&[
                        ("type", "booking_cancelled"),
                        ("bookingId", booking_id.as_str()),
                    ]),
                )
                .await;
        }
    }

    cache_and_emit(
        state,
        &booking_id,
        json!({
            "status": "CANCELLED",
            "operatorName": operator_name,
            "operatorId": operator_id,
            "customerId": customer_id,
            "cancelRequested": false,
        }),
    )
    .await;

    Ok(())
}

async fn on_completed(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    cache_and_emit(
        state,
        &booking_id,
        json!({
            "status": "COMPLETED",
            "operatorName": p.get("operatorName").cloned().unwrap_or(Value::Null),
            "operatorId": p.get("operatorId").cloned().unwrap_or(Value::Null),
            "customerId": p.get("customerId").cloned().unwrap_or(Value::Null),
            "isPaid": p.get("isPaid").and_then(|v| v.as_bool()).unwrap_or(false),
            "workerPaidConfirmed": p.get("workerPaidConfirmed").and_then(|v| v.as_bool()).unwrap_or(false),
            "customerPaidConfirmed": p.get("customerPaidConfirmed").and_then(|v| v.as_bool()).unwrap_or(false),
        }),
    )
    .await;

    if let Some(op) = p.get("operatorId").and_then(|v| v.as_str()) {
        workers::set_worker_status(state, op, "available").await;
    }
    Ok(())
}

async fn on_payment_confirmed(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    cache_and_emit(
        state,
        &booking_id,
        json!({
            "status": p.get("status").and_then(|v| v.as_str()).unwrap_or("COMPLETED"),
            "operatorName": p.get("operatorName").cloned().unwrap_or(Value::Null),
            "operatorId": p.get("operatorId").cloned().unwrap_or(Value::Null),
            "customerId": p.get("customerId").cloned().unwrap_or(Value::Null),
            "isPaid": p.get("isPaid").and_then(|v| v.as_bool()).unwrap_or(false),
            "workerPaidConfirmed": p.get("workerPaidConfirmed").and_then(|v| v.as_bool()).unwrap_or(false),
            "customerPaidConfirmed": p.get("customerPaidConfirmed").and_then(|v| v.as_bool()).unwrap_or(false),
        }),
    )
    .await;
    Ok(())
}

async fn cache_and_emit(state: &AppState, booking_id: &str, payload: Value) {
    let status = payload
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_uppercase();
    let customer_id = payload.get("customerId").and_then(|v| v.as_str());
    let operator_id = payload.get("operatorId").and_then(|v| v.as_str());
    let customer_update = async {
        if let Some(cid) = customer_id {
            let mut customer_payload = payload.clone();
            customer_payload["bookingId"] = json!(booking_id);
            customer_payload["id"] = json!(booking_id);
            if status != "ACCEPTED" && status != "ARRIVED" {
                customer_payload["arrivalOtp"] = Value::Null;
            }
            state
                .realtime
                .emit_to_user(cid, "booking_status_update", &customer_payload)
                .await;
        }
    };
    let worker_update = async {
        if let Some(oid) = operator_id {
            let mut worker_payload = payload.clone();
            worker_payload["bookingId"] = json!(booking_id);
            worker_payload["id"] = json!(booking_id);
            worker_payload["arrivalOtp"] = Value::Null;
            state
                .realtime
                .emit_to_user(oid, "booking_status_update", &worker_payload)
                .await;
        }
    };
    let _ = tokio::time::timeout(OPTIONAL_REDIS_TIMEOUT, async {
        tokio::join!(
            state.redis.cache_booking_status(booking_id, &payload),
            customer_update,
            worker_update,
        )
    })
    .await;
}

async fn get_notified_worker_ids(state: &AppState, booking_id: &str) -> Vec<String> {
    let Ok(id) = uuid::Uuid::parse_str(booking_id) else { return vec![]; };
    sqlx::query_scalar(
        "SELECT worker_id::text FROM booking_offer_recipients WHERE booking_id=$1",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default()
}

fn str_field(p: &Value, key: &str) -> Result<String, String> {
    p.get(key)
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| format!("missing {}", key))
}
