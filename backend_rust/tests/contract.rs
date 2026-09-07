//! Contract tests — run against a live API to verify Nest/Rust parity.
//!
//! Usage:
//!   API_BASE=http://localhost:3000 cargo test --test contract -- --nocapture

use std::env;

fn base_url() -> String {
    env::var("API_BASE").unwrap_or_else(|_| "http://localhost:3000".into())
}

#[tokio::test]
async fn root_returns_hello_world() {
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/", base_url()))
        .send()
        .await
        .expect("request failed");
    assert!(resp.status().is_success());
    let body = resp.text().await.expect("body");
    assert!(body.contains("Hello World"));
}

#[tokio::test]
async fn gateway_status_shape() {
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/payments/gateway-status", base_url()))
        .send()
        .await
        .expect("request failed");
    assert!(resp.status().is_success());
    let json: serde_json::Value = resp.json().await.expect("json");
    assert!(json.get("razorpay").is_some());
    assert!(json.get("upi").is_some());
    assert_eq!(json["upi"]["available"], false);
    assert_eq!(json["upi"]["needsApiKey"], true);
}

#[tokio::test]
async fn cities_public_list() {
    let client = reqwest::Client::new();
    let resp = client
        .get(format!("{}/cities", base_url()))
        .send()
        .await
        .expect("request failed");
    assert!(resp.status().is_success());
    let json: serde_json::Value = resp.json().await.expect("json");
    assert!(json.is_array());
}

#[tokio::test]
async fn auth_request_otp_shape() {
    let client = reqwest::Client::new();
    let resp = client
        .post(format!("{}/auth/request-otp", base_url()))
        .json(&serde_json::json!({ "phone": "+919999999999" }))
        .send()
        .await
        .expect("request failed");
    assert!(resp.status().is_success());
    let json: serde_json::Value = resp.json().await.expect("json");
    assert_eq!(json["message"], "OTP sent successfully");
}
