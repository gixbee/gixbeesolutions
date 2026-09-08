use axum::{
    extract::{Path, State},
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::AppResult;
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

const RING_TIMEOUT_SECONDS: u64 = 45;

pub fn routes() -> Router<AppState> {
    Router::new().route("/bookings/{id}/webrtc-config", get(webrtc_config))
}

async fn webrtc_config(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let _bid = Uuid::parse_str(&id)?;
    Ok(Json(ice_servers(&state)))
}

pub fn ice_servers(state: &AppState) -> Value {
    let stun = state
        .config
        .webrtc_stun_urls
        .split(',')
        .map(|s| json!({ "urls": s.trim() }))
        .collect::<Vec<_>>();
    let mut ice = stun;
    if let Some(turn_urls) = &state.config.webrtc_turn_urls {
        for url in turn_urls.split(',') {
            ice.push(json!({
                "urls": url.trim(),
                "username": state.config.webrtc_turn_username,
                "credential": state.config.webrtc_turn_credential,
            }));
        }
    }
    json!({ "iceServers": ice })
}

fn session_key(booking_id: &str) -> String {
    format!("voice_call:booking:{booking_id}")
}

async fn callable_participant(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
) -> Result<(String, String), String> {
    let bid = Uuid::parse_str(booking_id).map_err(|_| "Booking not found".to_string())?;
    let uid = Uuid::parse_str(user_id).map_err(|_| "Forbidden".to_string())?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, "customerId", "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "Booking not found".to_string())?;

    let status = row.get::<String, _>("status");
    if !matches!(
        status.as_str(),
        "ACCEPTED" | "CONFIRMED" | "ARRIVED" | "ACTIVE"
    ) {
        return Err("Calls are only available during an active booking".into());
    }

    let customer = row.get::<Uuid, _>("customerId");
    let operator = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();
    if customer == uid {
        let peer = operator
            .map(|u| u.to_string())
            .ok_or_else(|| "No worker assigned yet".to_string())?;
        return Ok(("customer".into(), peer));
    }
    if operator == Some(uid) {
        return Ok(("operator".into(), customer.to_string()));
    }
    Err("Forbidden".into())
}

pub async fn invite_call(
    state: &AppState,
    booking_id: &str,
    caller_id: &str,
    data: &Value,
) -> Result<Value, String> {
    let (_role, peer_id) = callable_participant(state, booking_id, caller_id).await?;
    let caller_name = data
        .get("callerName")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .unwrap_or("Gixbee user");

    let session = json!({
        "callId": Uuid::new_v4().to_string(),
        "bookingId": booking_id,
        "callerId": caller_id,
        "calleeId": peer_id,
        "status": "ringing",
        "createdAt": chrono::Utc::now().to_rfc3339(),
    });
    state
        .redis
        .set(&session_key(booking_id), &session.to_string(), RING_TIMEOUT_SECONDS)
        .await
        .map_err(|e| e.to_string())?;

    let payload = json!({
        "callId": session["callId"],
        "bookingId": booking_id,
        "callerId": caller_id,
        "calleeId": peer_id,
        "callerName": caller_name,
        "skill": "your booking",
        "ok": true,
    });
    state
        .realtime
        .emit_to_user(&peer_id, "voice_call_invite", &payload)
        .await;
    Ok(payload)
}

pub async fn accept_call(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
    data: &Value,
) -> Result<Value, String> {
    let raw = state
        .redis
        .get(&session_key(booking_id))
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "No active call".to_string())?;
    let session: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    if session["calleeId"].as_str() != Some(user_id) {
        return Err("Forbidden".into());
    }
    if let Some(call_id) = data.get("callId").and_then(|v| v.as_str()) {
        if session["callId"].as_str() != Some(call_id) {
            return Err("Stale call id".into());
        }
    }
    let active = json!({
        "callId": session["callId"],
        "bookingId": booking_id,
        "callerId": session["callerId"],
        "calleeId": session["calleeId"],
        "status": "active",
        "createdAt": session["createdAt"],
    });
    state
        .redis
        .set(&session_key(booking_id), &active.to_string(), 3600)
        .await
        .map_err(|e| e.to_string())?;
    let caller_id = session["callerId"].as_str().unwrap_or("");
    let payload = json!({
        "ok": true,
        "callId": session["callId"],
        "bookingId": booking_id,
        "callerId": session["callerId"],
        "calleeId": session["calleeId"],
    });
    state
        .realtime
        .emit_to_user(caller_id, "voice_call_accept", &payload)
        .await;
    Ok(payload)
}

pub async fn reject_call(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
) -> Result<Value, String> {
    let raw = state
        .redis
        .get(&session_key(booking_id))
        .await
        .map_err(|e| e.to_string())?;
    if raw.is_none() {
        return Ok(json!({ "ok": true }));
    }
    let session: Value = serde_json::from_str(&raw.unwrap()).map_err(|e| e.to_string())?;
    let caller = session["callerId"].as_str().unwrap_or("");
    let callee = session["calleeId"].as_str().unwrap_or("");
    if user_id != caller && user_id != callee {
        return Err("Not a call participant".into());
    }
    state.redis.del(&session_key(booking_id)).await.ok();
    let peer = if user_id == caller { callee } else { caller };
    state
        .realtime
        .emit_to_user(
            peer,
            "voice_call_reject",
            &json!({
                "callId": session["callId"],
                "bookingId": booking_id,
                "by": user_id,
            }),
        )
        .await;
    Ok(json!({ "ok": true }))
}

pub async fn hangup_call(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
) -> Result<Value, String> {
    let raw = state
        .redis
        .get(&session_key(booking_id))
        .await
        .map_err(|e| e.to_string())?;
    if let Some(raw) = raw {
        let session: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
        state.redis.del(&session_key(booking_id)).await.ok();
        let caller = session["callerId"].as_str().unwrap_or("");
        let callee = session["calleeId"].as_str().unwrap_or("");
        let peer = if user_id == caller { callee } else { caller };
        state
            .realtime
            .emit_to_user(
                peer,
                "voice_call_hangup",
                &json!({
                    "callId": session["callId"],
                    "bookingId": booking_id,
                    "by": user_id,
                }),
            )
            .await;
    }
    Ok(json!({ "ok": true }))
}

pub async fn relay_signal(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
    data: &Value,
) -> Result<Value, String> {
    let raw = state
        .redis
        .get(&session_key(booking_id))
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "No active call".to_string())?;
    let session: Value = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    let caller = session["callerId"].as_str().unwrap_or("");
    let callee = session["calleeId"].as_str().unwrap_or("");
    if user_id != caller && user_id != callee {
        return Err("Forbidden".into());
    }
    if let Some(call_id) = data.get("callId").and_then(|v| v.as_str()) {
        if session["callId"].as_str() != Some(call_id) {
            return Err("Stale call id".into());
        }
    }
    let peer = if user_id == caller { callee } else { caller };
    state
        .realtime
        .emit_to_user(
            peer,
            "voice_call_signal",
            &json!({
                "callId": session["callId"],
                "bookingId": booking_id,
                "from": user_id,
                "signal": data.get("signal"),
            }),
        )
        .await;
    Ok(json!({ "ok": true }))
}
