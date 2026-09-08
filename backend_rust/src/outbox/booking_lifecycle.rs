use serde_json::{json, Value};
use tracing::error;

use crate::jobs;
use crate::state::AppState;
use crate::workers;

pub async fn handle(state: &AppState, event_type: &str, payload: &Value) -> Result<(), String> {
    match event_type {
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
    let completion_otp = str_field(p, "completionOtp")?;

    state
        .redis
        .save_otp(&format!("otp:booking:{}:arrival", booking_id), &arrival_otp)
        .await
        .map_err(|e| e.to_string())?;
    state
        .redis
        .save_otp(&format!("otp:booking:{}:completion", booking_id), &completion_otp)
        .await
        .map_err(|e| e.to_string())?;

    if attempt == 1 {
        jobs::schedule_request_timeout(state.clone(), booking_id.clone(), 1);
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

    let notified_ids: Vec<String> = p
        .get("notifiedWorkerIds")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let mut notified_ok = Vec::new();
    for wid in &notified_ids {
        if state
            .redis
            .add_pending_booking(wid, &booking_id)
            .await
            .is_ok()
        {
            notified_ok.push(wid.clone());
        }
    }
    if notified_ok.is_empty() {
        return Ok(());
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

    for wid in &notified_ok {
        state
            .realtime
            .emit_to_user(wid, "new_booking_request", &socket_payload)
            .await;
    }

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

    let existing = if attempt > 1 {
        get_notified_worker_ids(state, &booking_id).await
    } else {
        vec![]
    };
    let merged: Vec<String> = existing
        .into_iter()
        .chain(notified_ok.into_iter())
        .collect::<std::collections::HashSet<_>>()
        .into_iter()
        .collect();
    state
        .redis
        .set(
            &format!("booking:notified:{}", booking_id),
            &serde_json::to_string(&merged).unwrap_or("[]".to_string()),
            60 * 60,
        )
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}

async fn on_accepted(state: &AppState, p: &Value) -> Result<(), String> {
    let booking_id = str_field(p, "bookingId")?;
    let worker_id = str_field(p, "workerId")?;
    let customer_id = p.get("customerId").and_then(|v| v.as_str());
    let operator_name = p.get("operatorName").and_then(|v| v.as_str());
    let arrival_otp = p.get("arrivalOtp").and_then(|v| v.as_str());

    workers::set_worker_status(state, &worker_id, "busy").await;
    let _ = state.redis.remove_pending_booking(&worker_id, &booking_id).await;

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

    clear_all_notified_pending(state, &booking_id).await;

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
        let _ = state
            .redis
            .remove_pending_booking(&worker_id, cancelled_id)
            .await;
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

    jobs::schedule_seven_minute_reminder(state.clone(), booking_id.clone());
    jobs::schedule_ten_minute_gps_check(state.clone(), booking_id.clone());

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
        let _ = state.redis.remove_pending_booking(op, &booking_id).await;
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
    clear_all_notified_pending(state, &booking_id).await;

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
    let _ = state.redis.cache_booking_status(booking_id, &payload).await;
    let status = payload
        .get("status")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_uppercase();
    let customer_id = payload.get("customerId").and_then(|v| v.as_str());
    let operator_id = payload.get("operatorId").and_then(|v| v.as_str());
    let arrival_otp = payload.get("arrivalOtp").cloned();

    if let Some(cid) = customer_id {
        let mut customer_payload = payload.clone();
        if let Some(obj) = customer_payload.as_object_mut() {
            obj.insert("bookingId".into(), json!(booking_id));
            obj.insert("id".into(), json!(booking_id));
            let otp = if status == "ACCEPTED" || status == "ARRIVED" {
                arrival_otp
            } else {
                None
            };
            obj.insert("arrivalOtp".into(), otp.unwrap_or(Value::Null));
        }
        state
            .realtime
            .emit_to_user(cid, "booking_status_update", &customer_payload)
            .await;
    }
    if let Some(oid) = operator_id {
        let mut worker_payload = payload.clone();
        if let Some(obj) = worker_payload.as_object_mut() {
            obj.insert("bookingId".into(), json!(booking_id));
            obj.insert("id".into(), json!(booking_id));
            obj.insert("arrivalOtp".into(), Value::Null);
        }
        state
            .realtime
            .emit_to_user(oid, "booking_status_update", &worker_payload)
            .await;
    }
}

async fn get_notified_worker_ids(state: &AppState, booking_id: &str) -> Vec<String> {
    let raw = state
        .redis
        .get(&format!("booking:notified:{}", booking_id))
        .await
        .ok()
        .flatten();
    match raw {
        Some(s) => serde_json::from_str::<Vec<String>>(&s).unwrap_or_default(),
        None => vec![],
    }
}

async fn clear_all_notified_pending(state: &AppState, booking_id: &str) {
    let notified = get_notified_worker_ids(state, booking_id).await;
    for wid in notified {
        let _ = state.redis.remove_pending_booking(&wid, booking_id).await;
    }
    let _ = state
        .redis
        .del(&format!("booking:notified:{}", booking_id))
        .await;
}

fn str_field(p: &Value, key: &str) -> Result<String, String> {
    p.get(key)
        .and_then(|v| v.as_str())
        .map(String::from)
        .ok_or_else(|| format!("missing {}", key))
}
