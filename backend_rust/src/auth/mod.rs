use axum::{
    extract::State,
    http::HeaderMap,
    routing::{get, patch, post},
    Json, Router,
};
use rand::Rng;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use tokio::io::AsyncReadExt;
use uuid::Uuid;

use crate::common::money::NEW_USER_WALLET_BONUS;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::{
    hash_refresh_token, sign_access, sign_refresh, verify_refresh, AuthUser, JwtClaims,
};
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/request-otp", post(request_otp))
        .route("/verify-otp", post(verify_otp))
        .route("/confirm-otp", post(confirm_otp))
        .route("/refresh", post(refresh_token))
        .route("/profile", get(get_profile))
        .route("/profile/setup", post(complete_profile_setup))
        .route("/push-token", patch(update_push_token))
        .route("/fcm-token", patch(update_fcm_token))
        .route("/admin-login", post(admin_login))
}

#[derive(Deserialize)]
struct RequestOtpBody {
    phone: String,
}

#[derive(Serialize)]
struct RequestOtpResponse {
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    devOtp: Option<String>,
}

async fn request_otp(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<RequestOtpBody>,
) -> AppResult<Json<RequestOtpResponse>> {
    limit_otp(&state, &headers, &body.phone, "send", 3, 20).await?;
    let otp = format!("{:06}", rand::random::<u32>() % 900_000 + 100_000);
    let key = format!("otp:{}", body.phone);
    with_otp_store(state.redis.save_otp(&key, &otp)).await?;

    if let (Some(auth_key), Some(template_id)) = (
        &state.config.msg91_auth_key,
        &state.config.msg91_template_id,
    ) {
        send_msg91_otp(&state, &body.phone, &otp, auth_key, template_id).await?;
    } else if state.config.is_production {
        return Err(AppError::ServiceUnavailable(
            "Could not send OTP SMS — please try again shortly".into(),
        ));
    }

    let otp_echo = state.config.allow_otp_echo && !state.config.is_production;
    if otp_echo {
        tracing::info!("[DEV ONLY] OTP for {}: {}", body.phone, otp);
        return Ok(Json(RequestOtpResponse {
            message: "OTP sent successfully".into(),
            devOtp: Some(otp),
        }));
    }

    if state.config.msg91_auth_key.is_none() && !state.config.is_production {
        tracing::info!("[DEV] OTP for {}: {}", body.phone, otp);
    }

    Ok(Json(RequestOtpResponse {
        message: "OTP sent successfully".into(),
        devOtp: None,
    }))
}

async fn with_otp_store<T>(
    operation: impl std::future::Future<Output = anyhow::Result<T>>,
) -> AppResult<T> {
    match tokio::time::timeout(std::time::Duration::from_secs(2), operation).await {
        Ok(Ok(value)) => return Ok(value),
        Ok(Err(error)) => tracing::warn!(%error, "OTP storage temporarily unavailable"),
        Err(error) => tracing::warn!(%error, "OTP storage request timed out"),
    }
    Err(AppError::ServiceUnavailable(
        "Phone verification is temporarily unavailable. Please try again shortly.".into(),
    ))
}

async fn limit_otp(
    state: &AppState,
    headers: &HeaderMap,
    phone: &str,
    action: &str,
    phone_limit: u32,
    ip_limit: u32,
) -> AppResult<()> {
    if !state.config.is_production {
        return Ok(());
    }
    use sha2::{Digest, Sha256};
    let digits: String = phone.chars().filter(char::is_ascii_digit).collect();
    let number = digits.strip_prefix("91").filter(|rest| rest.len() == 10).unwrap_or(&digits);
    let phone_key = format!("otp-limit:{action}:phone:{:x}", Sha256::digest(number.as_bytes()));
    // The published Nginx proxy overwrites X-Real-IP and Rust has no public port.
    let ip = headers.get("x-real-ip").and_then(|v| v.to_str().ok())
        .and_then(|ip| ip.parse::<std::net::IpAddr>().ok());
    let ip_key = ip.map(|ip| format!("otp-limit:{action}:ip:{ip}"));
    if with_otp_store(state.redis.allow_otp_attempt(&phone_key, ip_key.as_deref(), phone_limit, ip_limit)).await? {
        Ok(())
    } else {
        Err(AppError::TooManyRequests("Too many OTP requests. Please try again in a few minutes.".into()))
    }
}

async fn send_msg91_otp(
    state: &AppState,
    phone: &str,
    otp: &str,
    auth_key: &str,
    template_id: &str,
) -> AppResult<()> {
    let payload = serde_json::json!({
        "template_id": template_id,
        "short_url": "0",
        "recipients": [{ "mobiles": phone.trim_start_matches('+'), "var": otp }]
    });
    let resp = state
        .http
        .post("https://control.msg91.com/api/v5/flow/")
        .header("authkey", auth_key)
        .json(&payload)
        .timeout(std::time::Duration::from_secs(8))
        .send()
        .await;
    match resp {
        Ok(response) if response.status().is_success() => {}
        Ok(response) => {
            tracing::warn!(status = %response.status(), "MSG91 rejected the SMS request");
            return Err(AppError::ServiceUnavailable(
                "Could not send OTP SMS. Please try again shortly.".into(),
            ));
        }
        Err(error) => {
            tracing::warn!(%error, "MSG91 SMS request failed");
            return Err(AppError::ServiceUnavailable(
                "Could not send OTP SMS. Please try again shortly.".into(),
            ));
        }
    }
    Ok(())
}

#[derive(Deserialize)]
struct VerifyOtpBody {
    phone: String,
    otp: String,
}

#[derive(Serialize)]
struct TokenPair {
    accessToken: String,
    refreshToken: String,
}

async fn verify_otp(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<VerifyOtpBody>,
) -> AppResult<Json<TokenPair>> {
    limit_otp(&state, &headers, &body.phone, "verify", 8, 40).await?;
    let key = format!("otp:{}", body.phone);
    let stored = with_otp_store(state.redis.consume_otp(&key)).await?;
    if stored.as_deref() != Some(body.otp.as_str()) {
        return Err(AppError::Unauthorized("Invalid or expired OTP".into()));
    }

    let existing = sqlx::query(r#"SELECT id FROM users WHERE "phoneNumber" = $1"#)
        .bind(&body.phone)
        .fetch_optional(&state.db)
        .await?;

    let user_id = if let Some(row) = existing {
        row.get::<Uuid, _>("id").to_string()
    } else {
        let id = Uuid::new_v4();
        sqlx::query(
            r#"
            INSERT INTO users (id, "phoneNumber", name, role, "walletBalance", "isVerified", "hasWorkerProfile", "isAvailableForWork", "profileSetupPending")
            VALUES ($1, $2, '', 'CUSTOMER', $3, true, false, true, true)
            "#,
        )
        .bind(id)
        .bind(&body.phone)
        .bind(NEW_USER_WALLET_BONUS)
        .execute(&state.db)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO wallet_transactions (id, "userId", amount, type, description)
            VALUES ($1, $2, 30, 'CREDIT', 'Welcome Bonus')
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(id)
        .execute(&state.db)
        .await?;

        sqlx::query(
            r#"
            INSERT INTO job_credits (id, "userId", balance)
            VALUES ($1, $2, 30)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(id)
        .execute(&state.db)
        .await?;

        id.to_string()
    };

    generate_token_pair(&state, &user_id, &body.phone, "CUSTOMER").await
}

/// Proves possession of a phone (business listing) without logging into it.
async fn confirm_otp(
    State(state): State<AppState>,
    _user: AuthUser,
    headers: HeaderMap,
    Json(body): Json<VerifyOtpBody>,
) -> AppResult<Json<Value>> {
    limit_otp(&state, &headers, &body.phone, "verify", 8, 40).await?;
    let key = format!("otp:{}", body.phone);
    let stored = with_otp_store(state.redis.consume_otp(&key)).await?;
    if stored.as_deref() != Some(body.otp.as_str()) {
        return Err(AppError::Unauthorized("Invalid or expired OTP".into()));
    }
    Ok(Json(json!({ "verified": true })))
}

async fn generate_token_pair(
    state: &AppState,
    user_id: &str,
    phone: &str,
    role: &str,
) -> AppResult<Json<TokenPair>> {
    let claims = JwtClaims {
        sub: user_id.to_string(),
        phoneNumber: Some(phone.to_string()),
        role: Some(role.to_string()),
        staffRole: None,
        pages: vec![],
        username: None,
        displayName: None,
        r#type: None,
        exp: None,
        iat: None,
    };
    let access = sign_access(state, &claims)?;
    let refresh = sign_refresh(state, user_id)?;
    let hash = hash_refresh_token(&refresh);
    state
        .redis
        .set(&format!("refresh:{user_id}"), &hash, 30 * 24 * 60 * 60)
        .await?;
    Ok(Json(TokenPair {
        accessToken: access,
        refreshToken: refresh,
    }))
}

#[derive(Deserialize)]
struct RefreshBody {
    refreshToken: String,
}

#[derive(Serialize)]
struct AccessOnly {
    accessToken: String,
}

async fn refresh_token(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> AppResult<Json<AccessOnly>> {
    let claims = verify_refresh(&state, &body.refreshToken)?;
    if claims.r#type.as_deref() != Some("refresh") {
        return Err(AppError::Unauthorized("Invalid token type".into()));
    }
    let hash = hash_refresh_token(&body.refreshToken);
    let stored = state.redis.get(&format!("refresh:{}", claims.sub)).await?;
    if stored.as_deref() != Some(hash.as_str()) {
        return Err(AppError::Unauthorized("Refresh token revoked or expired".into()));
    }

    let row = sqlx::query(r#"SELECT "phoneNumber", role::text AS role FROM users WHERE id = $1"#)
        .bind(Uuid::parse_str(&claims.sub).map_err(|_| AppError::Unauthorized("User not found".into()))?)
        .fetch_optional(&state.db)
        .await?;
    let row = row.ok_or_else(|| AppError::Unauthorized("User not found".into()))?;
    let phone = row.get::<String, _>("phoneNumber");
    let role = row.get::<String, _>("role");

    let access_claims = JwtClaims {
        sub: claims.sub.clone(),
        phoneNumber: Some(phone),
        role: Some(role),
        staffRole: None,
        pages: vec![],
        username: None,
        displayName: None,
        r#type: None,
        exp: None,
        iat: None,
    };
    Ok(Json(AccessOnly {
        accessToken: sign_access(&state, &access_claims)?,
    }))
}

#[derive(Serialize)]
struct ProfileResponse {
    id: String,
    phone: String,
    name: String,
    email: Option<String>,
    avatar: Option<String>,
    role: String,
    profileSetupRequired: bool,
    hasWorkerProfile: bool,
    isAvailableForWork: bool,
    instantHelpBlocked: bool,
    lateCancelStrikeCount: i32,
    unblockCompensationAmountInr: Option<i32>,
    unblockCompensationDistanceKm: Option<f64>,
}

async fn get_profile(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<ProfileResponse>> {
    let uid = Uuid::parse_str(&user.user_id).map_err(|_| AppError::NotFound("User not found".into()))?;
    let row = sqlx::query(
        r#"
        SELECT u.id, u."phoneNumber", u.name,
               (u."profileSetupPending" OR (u."identityDetailsConfirmedAt" IS NULL
                AND btrim(COALESCE(u.name, '')) = '')) AS "profileSetupRequired",
               COALESCE(NULLIF(u."profileImageUrl", ''), tp."photoUrl") AS "profileImageUrl",
               u.role::text AS role, u."hasWorkerProfile",
               u."isAvailableForWork", u."instantHelpBlocked", u."lateCancelStrikeCount",
               u."unblockCompensationAmountInr", u."unblockCompensationDistanceKm"
        FROM users u
        LEFT JOIN talent_profiles tp ON tp."userId" = u.id
        WHERE u.id = $1
        "#,
    )
    .bind(uid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("User not found".into()))?;

    Ok(Json(ProfileResponse {
        id: row.get::<Uuid, _>("id").to_string(),
        phone: row.get("phoneNumber"),
        name: row.get::<Option<String>, _>("name").unwrap_or_default(),
        email: None,
        avatar: row.get("profileImageUrl"),
        role: row.get("role"),
        profileSetupRequired: row.get("profileSetupRequired"),
        hasWorkerProfile: row.get("hasWorkerProfile"),
        isAvailableForWork: row.get("isAvailableForWork"),
        instantHelpBlocked: row.get("instantHelpBlocked"),
        lateCancelStrikeCount: row.get("lateCancelStrikeCount"),
        unblockCompensationAmountInr: row.get("unblockCompensationAmountInr"),
        unblockCompensationDistanceKm: row
            .get::<Option<rust_decimal::Decimal>, _>("unblockCompensationDistanceKm")
            .map(|d| d.to_string().parse().unwrap_or(0.0)),
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ProfileSetupBody {
    name: String,
    date_of_birth: chrono::NaiveDate,
    gender: String,
    profile_image_url: String,
    confirmed_matches_document: bool,
}

async fn complete_profile_setup(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<ProfileSetupBody>,
) -> AppResult<Json<ProfileResponse>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let name = body.name.trim();
    if name.is_empty() || name.chars().count() > 150 || name.chars().any(char::is_control) {
        return Err(AppError::BadRequest("Enter the full name on your document".into()));
    }
    let today = (chrono::Utc::now() + chrono::Duration::minutes(330)).date_naive();
    if body.date_of_birth > today || body.date_of_birth < chrono::NaiveDate::from_ymd_opt(1900, 1, 1).unwrap() {
        return Err(AppError::BadRequest("Enter a valid date of birth".into()));
    }
    if !matches!(body.gender.as_str(), "FEMALE" | "MALE" | "TRANSGENDER" | "OTHER") {
        return Err(AppError::BadRequest("Select the gender shown on your document".into()));
    }
    if !body.confirmed_matches_document {
        return Err(AppError::BadRequest("Confirm your details match your document".into()));
    }
    // Accept a JPEG from the shared upload service. Parse and reconstruct the
    // filename before reading it so arbitrary URLs and file paths cannot be stored.
    let invalid_photo = || AppError::BadRequest("Upload a profile photo".into());
    let photo_id = body.profile_image_url.strip_prefix("/uploads/")
        .and_then(|url| url.strip_suffix(".jpg"))
        .and_then(|id| Uuid::parse_str(id).ok())
        .ok_or_else(invalid_photo)?;
    let filename = format!("{photo_id}.jpg");
    let photo_url = format!("/uploads/{filename}");
    let path = std::path::Path::new(&state.config.uploads_dir).join(filename);
    let mut photo = tokio::fs::File::open(path).await.map_err(|_| invalid_photo())?;
    let mut signature = [0u8; 3];
    photo.read_exact(&mut signature).await.map_err(|_| invalid_photo())?;
    if signature != [0xff, 0xd8, 0xff] {
        return Err(invalid_photo());
    }
    sqlx::query(
        r#"UPDATE users SET name=$2, "legalName"=$2, "dateOfBirth"=$3, gender=$4,
                  "profileImageUrl"=$5,
                  "identityDetailsConfirmedAt"=NOW(), "profileSetupPending"=false, "updatedAt"=NOW()
           WHERE id=$1 AND ("profileSetupPending" OR ("identityDetailsConfirmedAt" IS NULL
                 AND btrim(COALESCE(name, ''))=''))"#,
    )
    .bind(uid)
    .bind(name)
    .bind(body.date_of_birth)
    .bind(body.gender)
    .bind(photo_url)
    .execute(&state.db)
    .await?;
    get_profile(State(state), user).await
}

#[derive(Deserialize)]
struct PushTokenBody {
    pushToken: Option<String>,
    fcmToken: Option<String>,
}

#[derive(Serialize)]
struct MessageResponse {
    message: String,
}

async fn update_push_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<PushTokenBody>,
) -> AppResult<Json<MessageResponse>> {
    let token = body
        .pushToken
        .or(body.fcmToken)
        .ok_or_else(|| AppError::BadRequest("pushToken required".into()))?;
    update_token_inner(&state, &user.user_id, &token).await
}

async fn update_fcm_token(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<PushTokenBody>,
) -> AppResult<Json<MessageResponse>> {
    let token = body
        .fcmToken
        .or(body.pushToken)
        .ok_or_else(|| AppError::BadRequest("fcmToken required".into()))?;
    update_token_inner(&state, &user.user_id, &token).await
}

async fn update_token_inner(state: &AppState, user_id: &str, token: &str) -> AppResult<Json<MessageResponse>> {
    let uid = Uuid::parse_str(user_id).map_err(|_| AppError::NotFound("User not found".into()))?;
    sqlx::query(r#"UPDATE users SET "fcmToken" = $1 WHERE id = $2"#)
        .bind(token)
        .bind(uid)
        .execute(&state.db)
        .await?;
    state.redis.cache_fcm_token(user_id, token).await?;
    Ok(Json(MessageResponse {
        message: "Push token updated".into(),
    }))
}

#[derive(Deserialize)]
struct AdminLoginBody {
    username: Option<String>,
    password: Option<String>,
}

#[derive(Serialize)]
struct AdminLoginResponse {
    accessToken: String,
    staffRole: String,
    pages: Vec<String>,
    displayName: String,
    username: String,
}

async fn admin_login(
    State(state): State<AppState>,
    Json(body): Json<AdminLoginBody>,
) -> AppResult<Json<AdminLoginResponse>> {
    let user = body.username.clone().unwrap_or_default().trim().to_string();
    let pass = body.password.clone().unwrap_or_default();

    if let Some(staff) = validate_staff(&state, &user, &pass).await? {
        let pages = effective_pages(&staff);
        let claims = JwtClaims {
            sub: staff.id.clone(),
            phoneNumber: Some("admin".into()),
            role: Some("ADMIN".into()),
            staffRole: Some(staff.staff_role.clone()),
            pages: pages.clone(),
            username: Some(staff.username.clone()),
            displayName: Some(staff.display_name.clone()),
            r#type: None,
            exp: None,
            iat: None,
        };
        return Ok(Json(AdminLoginResponse {
            accessToken: sign_access(&state, &claims)?,
            staffRole: staff.staff_role,
            pages,
            displayName: staff.display_name,
            username: staff.username,
        }));
    }

    let admin_user = state.config.admin_username.as_deref();
    let admin_pass = state.config.admin_password.as_deref();
    if admin_user.is_none() || admin_pass.is_none() {
        return Err(AppError::Unauthorized("Admin credentials not configured on server".into()));
    }
    if user != admin_user.unwrap_or("") || pass != admin_pass.unwrap_or("") {
        return Err(AppError::Unauthorized("Invalid admin credentials".into()));
    }

    let pages = admin_portal_pages();
    let claims = JwtClaims {
        sub: "env-admin".into(),
        phoneNumber: Some("admin".into()),
        role: Some("ADMIN".into()),
        staffRole: Some("SUPER_ADMIN".into()),
        pages: pages.clone(),
        username: admin_user.map(|s| s.to_string()),
        displayName: Some("SuperAdmin".into()),
        r#type: None,
        exp: None,
        iat: None,
    };
    Ok(Json(AdminLoginResponse {
        accessToken: sign_access(&state, &claims)?,
        staffRole: "SUPER_ADMIN".into(),
        pages,
        displayName: "SuperAdmin".into(),
        username: admin_user.unwrap_or("admin").into(),
    }))
}

struct StaffRow {
    id: String,
    username: String,
    display_name: String,
    staff_role: String,
    pages: Option<Vec<String>>,
}

async fn validate_staff(state: &AppState, username: &str, password: &str) -> AppResult<Option<StaffRow>> {
    let row = sqlx::query(
        r#"SELECT id, username, "displayName", "staffRole", "allowedPages", "passwordHash" FROM admin_staff WHERE username = $1 AND "isActive" = true"#,
    )
    .bind(username)
    .fetch_optional(&state.db)
    .await?;

    if let Some(r) = row {
        let stored: String = r.get("passwordHash");
        if bcrypt::verify(password, &stored).unwrap_or(false) {
            let pages: Option<String> = r.get("allowedPages");
            let page_list = pages
                .map(|p| p.split(',').map(|s| s.trim().to_string()).collect())
                .unwrap_or_default();
            return Ok(Some(StaffRow {
                id: r.get::<Uuid, _>("id").to_string(),
                username: r.get::<String, _>("username"),
                display_name: r
                    .get::<Option<String>, _>("displayName")
                    .unwrap_or_else(|| username.to_string()),
                staff_role: r.get::<String, _>("staffRole"),
                pages: Some(page_list),
            }));
        }
    }
    Ok(None)
}

fn effective_pages(staff: &StaffRow) -> Vec<String> {
    if staff.staff_role == "SUPER_ADMIN" {
        return admin_portal_pages();
    }
    staff.pages.clone().unwrap_or_default()
}

fn admin_portal_pages() -> Vec<String> {
    vec![
        "dashboard".into(),
        "users".into(),
        "workers".into(),
        "bookings".into(),
        "disputes".into(),
        "verifications".into(),
        "master-entries".into(),
        "cities".into(),
        "support".into(),
        "logs".into(),
        "infrastructure".into(),
        "staff".into(),
    ]
}
