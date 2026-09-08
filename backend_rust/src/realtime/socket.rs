use serde::Deserialize;
use serde_json::{json, Value};
use socketioxide::adapter::Adapter;
use socketioxide::extract::{AckSender, Data, SocketRef, State};
use socketioxide::SocketIo;
use socketioxide_redis::{drivers::redis::redis_client as redis, RedisAdapter, RedisAdapterCtr};
use sqlx::Row;
use uuid::Uuid;

use crate::middleware::auth::verify_access;
use crate::state::AppState;
use crate::voice_calls;

type Io = SocketIo<RedisAdapter<socketioxide::adapter::Emitter>>;

#[derive(Debug, Deserialize, Default)]
pub struct SocketAuth {
    token: Option<String>,
    #[serde(rename = "Authorization")]
    authorization_header: Option<String>,
    authorization: Option<String>,
}

fn bearer_from_auth(auth: &SocketAuth) -> Option<String> {
    let raw = auth
        .token
        .as_deref()
        .or(auth.authorization_header.as_deref())
        .or(auth.authorization.as_deref())?;
    if raw.is_empty() {
        return None;
    }
    Some(if raw.starts_with("Bearer ") {
        raw.to_string()
    } else {
        format!("Bearer {}", raw)
    })
}

async fn verify_socket<A: Adapter>(
    socket: &SocketRef<A>,
    auth: &SocketAuth,
    state: &AppState,
) -> Result<(), String> {
    let bearer = bearer_from_auth(auth).ok_or_else(|| "Unauthorized".to_string())?;
    let token = bearer
        .strip_prefix("Bearer ")
        .ok_or_else(|| "Unauthorized".to_string())?;
    let claims = verify_access(state, token).map_err(|e| e.to_string())?;
    socket.extensions.insert(claims.sub);
    Ok(())
}

fn authed_user_id<A: Adapter>(socket: &SocketRef<A>) -> Option<String> {
    socket.extensions.get::<String>()
}

pub async fn build_socket_layer(
    redis_url: &str,
    state: AppState,
) -> Result<
    (
        socketioxide::layer::SocketIoLayer<RedisAdapter<socketioxide::adapter::Emitter>>,
        Io,
    ),
    anyhow::Error,
> {
    let redis_url = if redis_url.contains("protocol=") {
        redis_url.to_string()
    } else if redis_url.contains('?') {
        format!("{redis_url}&protocol=resp3")
    } else {
        format!("{redis_url}?protocol=resp3")
    };
    let client = redis::Client::open(redis_url.as_str())?;
    let adapter = RedisAdapterCtr::new_with_redis(&client).await?;
    let (layer, io) = SocketIo::builder()
        .with_state(state)
        .with_adapter::<RedisAdapter<_>>(adapter)
        .build_layer();
    Ok((layer, io))
}

pub fn register_handlers(io: &Io) {
    io.ns("/", on_connect);
}

async fn on_connect<A: Adapter>(
    socket: SocketRef<A>,
    auth: Data<SocketAuth>,
    State(state): State<AppState>,
) {
    if verify_socket(&socket, &auth, &state).await.is_err() {
        socket.disconnect().ok();
        return;
    }
    socket.on("joinUserRoom", on_join_user_room::<A>);
    socket.on("updateLocation", on_update_location::<A>);
    socket.on("joinJobRoom", on_join_job_room::<A>);
    socket.on("leaveJobRoom", on_leave_job_room::<A>);
    socket.on("voice_call_invite", on_voice_invite::<A>);
    socket.on("voice_call_accept", on_voice_accept::<A>);
    socket.on("voice_call_reject", on_voice_reject::<A>);
    socket.on("voice_call_hangup", on_voice_hangup::<A>);
    socket.on("voice_call_signal", on_voice_signal::<A>);
}

async fn on_join_user_room<A: Adapter>(socket: SocketRef<A>, ack: AckSender<A>) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&json!({ "error": "Unauthorized" })).ok();
            return;
        }
    };
    socket.join(format!("user_{}", user_id));
    ack.send(&json!({ "event": "joinedUserRoom", "data": user_id }))
        .ok();
}

async fn on_update_location<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => return,
    };
    let lat = data.get("lat").and_then(|v| v.as_f64());
    let lng = data.get("lng").and_then(|v| v.as_f64());
    if lat.is_none() || lng.is_none() {
        return;
    }
    let lat = lat.unwrap();
    let lng = lng.unwrap();
    let _ = state.redis.update_worker_location(&user_id, lat, lng).await;

    let payload = json!({
        "userId": user_id,
        "lat": lat,
        "lng": lng,
        "timestamp": chrono::Utc::now().to_rfc3339(),
    });

    if let Some(job_id) = data.get("jobId").and_then(|v| v.as_str()) {
        if !job_id.is_empty()
            && booking_participant(&state, job_id, &user_id).await.as_deref() == Ok("operator")
        {
            state
                .realtime
                .emit_to_job(job_id, "locationUpdated", &payload)
                .await;
        }
    } else {
        socket.emit("locationUpdated", &payload).ok();
    }
}

async fn on_join_job_room<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&json!({ "error": "Unauthorized" })).ok();
            return;
        }
    };
    let job_id = data.get("jobId").and_then(|v| v.as_str()).unwrap_or("");
    if job_id.is_empty() {
        ack.send(&json!({ "error": "Invalid job" })).ok();
        return;
    }
    match booking_participant(&state, job_id, &user_id).await {
        Ok(_) => {
            socket.join(format!("job_{}", job_id));
            ack.send(&json!({
                "event": "joined",
                "data": format!("Joined room job_{}", job_id)
            }))
            .ok();
        }
        Err(e) => {
            ack.send(&json!({ "error": e })).ok();
        }
    }
}

async fn on_leave_job_room<A: Adapter>(socket: SocketRef<A>, data: Data<Value>, ack: AckSender<A>) {
    if let Some(job_id) = data.get("jobId").and_then(|v| v.as_str()) {
        socket.leave(format!("job_{}", job_id));
        ack.send(&json!({
            "event": "left",
            "data": format!("Left room job_{}", job_id)
        }))
        .ok();
    } else {
        ack.send(&json!({ "event": "left", "data": null })).ok();
    }
}

async fn on_voice_invite<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let caller_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&voice_fail("Unauthorized")).ok();
            return;
        }
    };
    let booking_id = data.get("bookingId").and_then(|v| v.as_str()).unwrap_or("");
    if booking_id.is_empty() {
        ack.send(&voice_fail("bookingId required")).ok();
        return;
    }
    match voice_calls::invite_call(&state, booking_id, &caller_id, &data).await {
        Ok(resp) => {
            ack.send(&resp).ok();
        }
        Err(e) => {
            ack.send(&voice_fail(e)).ok();
        }
    }
}

async fn on_voice_accept<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&voice_fail("Unauthorized")).ok();
            return;
        }
    };
    let booking_id = data.get("bookingId").and_then(|v| v.as_str()).unwrap_or("");
    match voice_calls::accept_call(&state, booking_id, &user_id, &data).await {
        Ok(resp) => {
            ack.send(&resp).ok();
        }
        Err(e) => {
            ack.send(&voice_fail(e)).ok();
        }
    }
}

async fn on_voice_reject<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&voice_fail("Unauthorized")).ok();
            return;
        }
    };
    let booking_id = data.get("bookingId").and_then(|v| v.as_str()).unwrap_or("");
    match voice_calls::reject_call(&state, booking_id, &user_id).await {
        Ok(resp) => {
            ack.send(&resp).ok();
        }
        Err(e) => {
            ack.send(&voice_fail(e)).ok();
        }
    }
}

async fn on_voice_hangup<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&voice_fail("Unauthorized")).ok();
            return;
        }
    };
    let booking_id = data.get("bookingId").and_then(|v| v.as_str()).unwrap_or("");
    match voice_calls::hangup_call(&state, booking_id, &user_id).await {
        Ok(resp) => {
            ack.send(&resp).ok();
        }
        Err(e) => {
            ack.send(&voice_fail(e)).ok();
        }
    }
}

async fn on_voice_signal<A: Adapter>(
    socket: SocketRef<A>,
    data: Data<Value>,
    ack: AckSender<A>,
    State(state): State<AppState>,
) {
    let user_id = match authed_user_id(&socket) {
        Some(id) => id,
        None => {
            ack.send(&voice_fail("Unauthorized")).ok();
            return;
        }
    };
    let booking_id = data.get("bookingId").and_then(|v| v.as_str()).unwrap_or("");
    let signal = data.get("signal");
    if booking_id.is_empty() || signal.is_none() {
        ack.send(&voice_fail("bookingId and signal required")).ok();
        return;
    }
    match voice_calls::relay_signal(&state, booking_id, &user_id, &data).await {
        Ok(resp) => {
            ack.send(&resp).ok();
        }
        Err(e) => {
            ack.send(&voice_fail(e)).ok();
        }
    }
}

fn voice_fail(error: impl Into<String>) -> Value {
    json!({ "ok": false, "error": error.into() })
}

async fn booking_participant(
    state: &AppState,
    job_id: &str,
    user_id: &str,
) -> Result<String, String> {
    let bid = Uuid::parse_str(job_id).map_err(|_| "Invalid job".to_string())?;
    let uid = Uuid::parse_str(user_id).map_err(|_| "Unauthorized".to_string())?;
    let row = sqlx::query(r#"SELECT "customerId", "operatorId" FROM bookings WHERE id = $1"#)
        .bind(bid)
        .fetch_optional(&state.db)
        .await
        .map_err(|e| e.to_string())?;
    let row = row.ok_or_else(|| "Invalid job".to_string())?;
    let customer = row.get::<Uuid, _>("customerId");
    let operator = row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten();
    if customer == uid {
        return Ok("customer".into());
    }
    if operator == Some(uid) {
        return Ok("operator".into());
    }
    Err("Forbidden".into())
}
