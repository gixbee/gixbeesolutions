//! Socket.IO worker gateway — events mirrored from worker.gateway.ts.
//! Full Redis adapter wiring is initialized at server bootstrap.

use serde_json::Value;

pub fn register_events() -> Vec<&'static str> {
    vec!["updateLocation", "joinJobRoom", "leaveJobRoom"]
}

pub fn handle_event(event: &str, _payload: Value) -> Option<Value> {
    match event {
        "updateLocation" => None,
        "joinJobRoom" => None,
        "leaveJobRoom" => None,
        _ => None,
    }
}
