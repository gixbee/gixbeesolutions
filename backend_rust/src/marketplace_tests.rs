//! HTTP contracts against a disposable Nest-generated PostgreSQL schema.
//! Run explicitly with GIXBEE_TEST_DATABASE_URL and `cargo test marketplace_tests -- --ignored`.
use crate::{
    config::Config,
    middleware::auth::{sign_access, JwtClaims},
    state::AppState,
};
use axum::{
    body::{to_bytes, Body},
    http::Request,
    Router,
};
use serde_json::{json, Value};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

async fn fixture() -> (AppState, Router) {
    // Never load .env or accept a production database URL.
    let url =
        std::env::var("GIXBEE_TEST_DATABASE_URL").expect("Set the isolated contract database URL");
    let parsed = reqwest::Url::parse(&url).unwrap();
    assert!(matches!(parsed.host_str(), Some("127.0.0.1" | "localhost")));
    assert!(parsed.path().starts_with("/gixbee_contract_"));
    let config = Config {
        port: 0,
        node_env: "test".into(),
        is_production: false,
        database_url: url.clone(),
        redis_url: "redis://127.0.0.1:1".into(),
        redis_allow_memory_fallback: true,
        jwt_secret: "isolated-contract-test-secret-not-for-release".into(),
        admin_username: None,
        admin_password: None,
        allow_otp_echo: false,
        msg91_auth_key: None,
        msg91_template_id: None,
        msg91_sender_id: "TEST".into(),
        razorpay_key_id: None,
        razorpay_key_secret: None,
        razorpay_webhook_secret: None,
        firebase_key_path: None,
        firebase_project_id: None,
        firebase_client_email: None,
        firebase_private_key: None,
        aadhaar_client_id: None,
        aadhaar_client_secret: None,
        aadhaar_api_base: "http://127.0.0.1:1".into(),
        log_retention_days: 1,
        uploads_dir: "unused-test-uploads".into(),
        webrtc_stun_urls: String::new(),
        webrtc_turn_urls: None,
        webrtc_turn_username: None,
        webrtc_turn_credential: None,
    };
    let http = reqwest::Client::new();
    let state = AppState {
        cache: crate::cache::CacheConfig::from_env(),
        db: sqlx::postgres::PgPoolOptions::new()
            .max_connections(8)
            .connect(&url)
            .await
            .unwrap(),
        redis: Arc::new(crate::redis::RedisStore::for_tests()),
        fcm: Arc::new(crate::notifications::FcmService::from_config(
            &config,
            http.clone(),
        )),
        realtime: Arc::new(crate::realtime::RealtimeHub),
        config,
        http,
    };
    let router = crate::routes::api_router().with_state(state.clone());
    (state, router)
}

async fn user(state: &AppState) -> (Uuid, String) {
    let id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO users (id, "phoneNumber", name) VALUES ($1,$2,'Contract User')"#)
        .bind(id)
        .bind(format!("test-{}", id.simple()))
        .execute(&state.db)
        .await
        .unwrap();
    let token = sign_access(
        state,
        &JwtClaims {
            sub: id.to_string(),
            phoneNumber: None,
            role: Some("CUSTOMER".into()),
            staffRole: None,
            pages: vec![],
            username: None,
            displayName: None,
            r#type: None,
            exp: None,
            iat: None,
        },
    )
    .unwrap();
    (id, token)
}

async fn api(app: &Router, token: &str, method: &str, path: &str, body: Value) -> (u16, Value) {
    let mut request = Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json");
    if !token.is_empty() {
        request = request.header("authorization", format!("Bearer {token}"));
    }
    let response = app
        .clone()
        .oneshot(request.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status().as_u16();
    let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
    let value =
        serde_json::from_slice(&bytes).unwrap_or_else(|_| json!(String::from_utf8_lossy(&bytes)));
    (status, value)
}

#[tokio::test]
#[ignore = "Requires the isolated PostgreSQL contract schema"]
async fn business_ownership_and_calendar_persist() {
    let (state, app) = fixture().await;
    let (_, owner) = user(&state).await;
    let (stranger_id, stranger) = user(&state).await;
    let (status, business) = api(
        &app,
        &owner,
        "POST",
        "/businesses",
        json!({"name":"Test Rentals","type":"RENTAL","address":"Test City"}),
    )
    .await;
    assert_eq!(status, 200, "{business}");
    let path = format!("/businesses/{}", business["id"].as_str().unwrap());
    assert_eq!(
        api(&app, &stranger, "PATCH", &path, json!({"name":"Stolen"}))
            .await
            .0,
        404
    );
    assert_eq!(
        api(
            &app,
            &stranger,
            "POST",
            &format!("{path}/operators"),
            json!({"userId":stranger_id})
        )
        .await
        .0,
        404
    );
    let (status, _) = api(
        &app,
        &owner,
        "POST",
        &format!("{path}/calendar/offline"),
        json!({"date":"2027-01-10"}),
    )
    .await;
    assert_eq!(status, 400);
    let (status, catering) = api(
        &app,
        &owner,
        "POST",
        "/businesses",
        json!({"name":"Test Catering","type":"SERVICE","serviceType":"CATERING","address":"Test City"}),
    )
    .await;
    assert_eq!(status, 200, "{catering}");
    let calendar = format!("/businesses/{}/calendar/offline", catering["id"].as_str().unwrap());
    assert_eq!(
        api(&app, &stranger, "POST", &calendar, json!({"date":"2027-01-10"}))
            .await
            .0,
        404
    );
    let (status, result) = api(
        &app,
        &owner,
        "POST",
        &calendar,
        json!({"date":"2027-01-10"}),
    )
    .await;
    assert_eq!(status, 200, "{result}");
    assert_eq!(result["offlineDays"].as_array().unwrap().len(), 1);
    let catering_path = format!("/businesses/{}", catering["id"].as_str().unwrap());
    let (_, read) = api(&app, &owner, "GET", &catering_path, Value::Null).await;
    assert_eq!(read["offlineDays"], result["offlineDays"]);
    let (status, result) = api(
        &app,
        &owner,
        "DELETE",
        &format!("{calendar}?date=2027-01-10"),
        Value::Null,
    )
    .await;
    assert_eq!(status, 200, "{result}");
    assert_eq!(result["offlineDays"], json!([]));
    assert_eq!(
        api(&app, &owner, "GET", "/businesses/admin/all", Value::Null)
            .await
            .0,
        403
    );
    let admin = sign_access(
        &state,
        &JwtClaims {
            sub: Uuid::new_v4().to_string(),
            phoneNumber: None,
            role: Some("ADMIN".into()),
            staffRole: Some("STAFF".into()),
            pages: vec!["businesses".into()],
            username: None,
            displayName: None,
            r#type: None,
            exp: None,
            iat: None,
        },
    )
    .unwrap();
    let moderation = format!(
        "/businesses/admin/{}/status",
        business["id"].as_str().unwrap()
    );
    let (status, verified) = api(
        &app,
        &admin,
        "PATCH",
        &moderation,
        json!({"status":"VERIFIED"}),
    )
    .await;
    assert_eq!(status, 200, "{verified}");
    assert_eq!(verified["status"], "VERIFIED");
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &path,
            json!({"name":"A different business"})
        )
        .await
        .0,
        400
    );
}

#[tokio::test]
#[ignore = "Requires the isolated PostgreSQL contract schema"]
async fn rental_price_and_competing_confirmations() {
    let (state, app) = fixture().await;
    let (_, owner) = user(&state).await;
    let (_, renter) = user(&state).await;
    let (_, renter2) = user(&state).await;
    let (status, item) = api(
        &app,
        &owner,
        "POST",
        "/rentals",
        json!({"name":"Test Camera","hourlyRate":100,"dailyRate":1000,"minHoursToRent":2}),
    )
    .await;
    assert_eq!(status, 200, "{item}");
    let start = chrono::Utc::now() + chrono::Duration::days(2);
    let reserve = format!("/rentals/{}/reserve", item["id"].as_str().unwrap());
    let dates = json!({"startTime":start.to_rfc3339(),"endTime":(start+chrono::Duration::hours(49)).to_rfc3339()});
    let (status, first) = api(&app, &renter, "POST", &reserve, dates.clone()).await;
    assert_eq!(status, 200, "{first}");
    assert_eq!(
        first["totalPrice"]
            .as_str()
            .unwrap()
            .parse::<f64>()
            .unwrap(),
        3000.0
    );
    let (status, second) = api(&app, &renter2, "POST", &reserve, dates).await;
    assert_eq!(status, 200, "{second}");
    let first_path = format!("/rentals/reservations/{}", first["id"].as_str().unwrap());
    let second_path = format!("/rentals/reservations/{}", second["id"].as_str().unwrap());
    assert_eq!(
        api(
            &app,
            &renter,
            "PATCH",
            &format!("{first_path}/confirm"),
            Value::Null
        )
        .await
        .0,
        403
    );
    let a = format!("{first_path}/confirm");
    let b = format!("{second_path}/confirm");
    let (a, b) = tokio::join!(
        api(&app, &owner, "PATCH", &a, Value::Null),
        api(&app, &owner, "PATCH", &b, Value::Null)
    );
    let mut statuses = vec![a.0, b.0];
    statuses.sort();
    assert_eq!(statuses, vec![200, 409], "{a:?} {b:?}");
    let confirmed = if a.0 == 200 { first_path } else { second_path };
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &format!("{confirmed}/complete"),
            Value::Null
        )
        .await
        .0,
        409
    );
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &format!("{confirmed}/start"),
            Value::Null
        )
        .await
        .0,
        200
    );
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &format!("{confirmed}/complete"),
            Value::Null
        )
        .await
        .0,
        200
    );
}

#[tokio::test]
#[ignore = "Requires the isolated PostgreSQL contract schema"]
async fn hiring_deadline_returns_full_fee_once_when_nobody_is_interested() {
    let (state, app) = fixture().await;
    let (employer, token) = user(&state).await;
    let (candidate, _) = user(&state).await;
    let no_response = Uuid::new_v4();
    let has_response = Uuid::new_v4();
    let closed_early = Uuid::new_v4();

    for (id, deadline_offset) in [(no_response, -1), (has_response, -1), (closed_early, 1)] {
        sqlx::query(r#"INSERT INTO hiring_requests (id,"employerId","jobType","feeAmount","creditApplied","deadlineAt")
            VALUES ($1,$2,'Electrician',99,30,NOW()+make_interval(hours => $3))"#)
            .bind(id)
            .bind(employer)
            .bind(deadline_offset)
            .execute(&state.db)
            .await
            .unwrap();
    }
    sqlx::query(r#"INSERT INTO hiring_interests ("requestId","candidateId",response)
        VALUES ($1,$2,'INTERESTED')"#)
        .bind(has_response)
        .bind(candidate)
        .execute(&state.db)
        .await
        .unwrap();

    for (id, expected_coins) in [(no_response, 99.0), (has_response, 0.0), (closed_early, 0.0)] {
        let path = format!("/hiring/match/requests/{id}/close");
        let (status, detail) = api(&app, &token, "POST", &path, Value::Null).await;
        assert_eq!(status, 200, "{detail}");
        assert_eq!(detail["hiringCoinsReturned"].as_f64(), Some(expected_coins));
        assert_eq!(api(&app, &token, "POST", &path, Value::Null).await.0, 400);
    }
    let (status, balance) = api(&app, &token, "GET", "/hiring/match/credit", Value::Null).await;
    assert_eq!(status, 200, "{balance}");
    assert_eq!(balance["availableHiringCoins"], 99);
}

#[tokio::test]
#[ignore = "Requires the isolated PostgreSQL contract schema"]
async fn profiles_and_hiring_require_ownership_and_funding() {
    let (state, app) = fixture().await;
    let (owner_id, owner) = user(&state).await;
    let (candidate_id, stranger) = user(&state).await;
    let (status, profile) = api(&app,&owner,"POST","/hiring/match/preferences",json!({
        "jobType":"Electrician","skills":["Wiring"],"expectedSalary":20000,"preferredLocation":"Test City",
        "employmentType":"FULL_TIME","experienceYears":3,"noticePeriod":"DAYS_30"
    })).await;
    assert_eq!(status, 200, "{profile}");
    assert_eq!(profile["skills"], json!(["Wiring"]));
    assert_eq!(profile["employmentType"], "FT");
    let path = format!(
        "/hiring/match/preferences/{}",
        profile["id"].as_str().unwrap()
    );
    assert_eq!(
        api(&app, &stranger, "PATCH", &path, json!({"expectedSalary":1}))
            .await
            .0,
        404
    );
    assert_eq!(
        api(&app, &owner, "PATCH", &path, json!({"jobType":"Driver"}))
            .await
            .0,
        400
    );
    assert_eq!(api(&app, &owner, "DELETE", &path, Value::Null).await.0, 400);
    sqlx::query(r#"INSERT INTO businesses ("ownerId",name,location,type,status) VALUES ($1,'Test Hiring','Test City','HIRING','VERIFIED')"#)
        .bind(owner_id).execute(&state.db).await.unwrap();
    let criteria = json!({"jobType":"Electrician","salaryMin":10000,"salaryMax":25000,"skills":["Wiring"],"vacancies":1});
    let (status, quote) = api(
        &app,
        &owner,
        "POST",
        "/hiring/match/requests",
        criteria.clone(),
    )
    .await;
    assert_eq!(status, 200, "{quote}");
    assert_eq!(quote["needsPayment"], true);
    let count: i64 =
        sqlx::query_scalar(r#"SELECT COUNT(*) FROM hiring_requests WHERE "employerId"=$1"#)
            .bind(owner_id)
            .fetch_one(&state.db)
            .await
            .unwrap();
    assert_eq!(count, 0);
    sqlx::query(r#"UPDATE users SET "hiringCreditBalance"=49 WHERE id=$1"#)
        .bind(owner_id)
        .execute(&state.db)
        .await
        .unwrap();
    let (status, created) = api(&app, &owner, "POST", "/hiring/match/requests", criteria).await;
    assert_eq!(status, 200, "{created}");
    let path = format!(
        "/hiring/match/requests/{}",
        created["request"]["id"].as_str().unwrap()
    );
    assert_eq!(api(&app, "", "GET", &path, Value::Null).await.0, 401);
    assert_eq!(api(&app, &stranger, "GET", &path, Value::Null).await.0, 404);
    assert_eq!(api(&app, &owner, "GET", &path, Value::Null).await.0, 200);
    let (status, candidate) = api(
        &app,
        &stranger,
        "POST",
        "/hiring/match/preferences",
        json!({
            "jobType":"Electrician","expectedSalary":19000,"skills":["Wiring"],"employmentType":"FT"
        }),
    )
    .await;
    assert_eq!(status, 200, "{candidate}");
    let request_id = Uuid::parse_str(created["request"]["id"].as_str().unwrap()).unwrap();
    let interest_id = Uuid::new_v4();
    // A candidate response is durable before any employer decision or contact release.
    sqlx::query(r#"INSERT INTO hiring_interests (id,"requestId","candidateId","preferenceId",response,"respondedAt")
        VALUES ($1,$2,$3,$4,'INTERESTED',NOW()) ON CONFLICT ("requestId","candidateId") DO UPDATE SET response='INTERESTED',"respondedAt"=NOW()"#)
        .bind(interest_id).bind(request_id).bind(candidate_id).bind(Uuid::parse_str(candidate["id"].as_str().unwrap()).unwrap())
        .execute(&state.db).await.unwrap();
    let (_, detail) = api(&app, &owner, "GET", &path, Value::Null).await;
    assert!(detail["candidates"][0]["phone"].is_null(), "{detail}");
    let interest_path = format!(
        "/hiring/match/interests/{}/decision",
        detail["candidates"][0]["interestId"].as_str().unwrap()
    );
    assert_eq!(
        api(
            &app,
            &stranger,
            "PATCH",
            &interest_path,
            json!({"decision":"SHORTLISTED"})
        )
        .await
        .0,
        400
    );
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &interest_path,
            json!({"decision":"HIRED"})
        )
        .await
        .0,
        400
    );
    assert_eq!(
        api(
            &app,
            &owner,
            "PATCH",
            &interest_path,
            json!({"decision":"SHORTLISTED"})
        )
        .await
        .0,
        200
    );
    let (_, detail) = api(&app, &owner, "GET", &path, Value::Null).await;
    assert!(detail["candidates"][0]["phone"].is_null(), "{detail}");
    let share = format!(
        "/hiring/match/interests/{}/progress/share-contact",
        detail["candidates"][0]["interestId"].as_str().unwrap()
    );
    assert_eq!(
        api(&app, &stranger, "POST", &share, json!({})).await.0,
        200
    );
    let (_, detail) = api(&app, &owner, "GET", &path, Value::Null).await;
    assert!(detail["candidates"][0]["phone"].is_string(), "{detail}");
}

#[tokio::test]
#[ignore = "Requires the isolated PostgreSQL contract schema"]
async fn hiring_deadline_delivers_shortlist_idempotently() {
    let (state, app) = fixture().await;
    let (employer, _token) = user(&state).await;
    let request_id = Uuid::new_v4();
    sqlx::query(r#"INSERT INTO hiring_requests (id,"employerId","jobType","feeAmount","creditApplied","deadlineAt")
        VALUES ($1,$2,'Expired Contract Role',49,49,NOW()-INTERVAL '1 minute')"#)
        .bind(request_id).bind(employer).execute(&state.db).await.unwrap();
    let (a, b) = tokio::join!(
        crate::matching::poll_for_tests(&state),
        crate::matching::poll_for_tests(&state)
    );
    a.unwrap();
    b.unwrap();
    let status: String = sqlx::query_scalar("SELECT status::text FROM hiring_requests WHERE id=$1")
        .bind(request_id)
        .fetch_one(&state.db)
        .await
        .unwrap();
    assert_eq!(status, "DELIVERED");
    let events: i64 =
        sqlx::query_scalar(r#"SELECT COUNT(*) FROM outbox_events WHERE "aggregateId"=$1"#)
            .bind(request_id)
            .fetch_one(&state.db)
            .await
            .unwrap();
    assert_eq!(events, 1);
    let _ = app;
}
