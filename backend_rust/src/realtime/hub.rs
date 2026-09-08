use serde::Serialize;
use socketioxide::SocketIo;
use socketioxide_redis::RedisAdapter;
use std::sync::OnceLock;
use tracing::warn;

static IO: OnceLock<SocketIo<RedisAdapter<socketioxide::adapter::Emitter>>> = OnceLock::new();

/// Cheaply cloneable handle for emitting Socket.IO events from HTTP handlers and background jobs.
pub struct RealtimeHub;

impl RealtimeHub {
    pub fn bind(io: SocketIo<RedisAdapter<socketioxide::adapter::Emitter>>) {
        let _ = IO.set(io);
    }

    pub async fn emit_to_user(&self, user_id: &str, event: &str, payload: impl Serialize) {
        if user_id.is_empty() || event.is_empty() {
            return;
        }
        let Some(io) = IO.get() else {
            return;
        };
        let room = format!("user_{}", user_id);
        let Some(ns) = io.of("/") else {
            warn!("socket namespace / not registered; skip emit {event} -> {user_id}");
            return;
        };
        if let Err(e) = ns.to(room).emit(event, &payload).await {
            warn!("socket emit {event} -> {user_id}: {e}");
        }
    }

    pub async fn emit_to_job(&self, job_id: &str, event: &str, payload: impl Serialize) {
        if job_id.is_empty() || event.is_empty() {
            return;
        }
        let Some(io) = IO.get() else {
            return;
        };
        let room = format!("job_{}", job_id);
        let Some(ns) = io.of("/") else {
            warn!("socket namespace / not registered; skip emit {event} -> job {job_id}");
            return;
        };
        if let Err(e) = ns.to(room).emit(event, &payload).await {
            warn!("socket emit {event} -> job {job_id}: {e}");
        }
    }
}
