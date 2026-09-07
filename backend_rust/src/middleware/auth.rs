use axum::{
    extract::{FromRequestParts, Request},
    http::{header::AUTHORIZATION, request::Parts, StatusCode},
    middleware::Next,
    response::Response,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::{AppError, AppResult};
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JwtClaims {
    pub sub: String,
    #[serde(default)]
    pub phoneNumber: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub staffRole: Option<String>,
    #[serde(default)]
    pub pages: Vec<String>,
    #[serde(default)]
    pub username: Option<String>,
    #[serde(default)]
    pub displayName: Option<String>,
    #[serde(default)]
    pub r#type: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub user_id: String,
    pub phone_number: Option<String>,
    pub role: Option<String>,
    pub staff_role: Option<String>,
    pub pages: Vec<String>,
    pub username: Option<String>,
    pub display_name: Option<String>,
}

impl From<JwtClaims> for AuthUser {
    fn from(c: JwtClaims) -> Self {
        Self {
            user_id: c.sub,
            phone_number: c.phoneNumber,
            role: c.role,
            staff_role: c.staffRole,
            pages: c.pages,
            username: c.username,
            display_name: c.displayName,
        }
    }
}

pub fn sign_access(state: &AppState, claims: &JwtClaims) -> AppResult<String> {
    encode(
        &Header::default(),
        claims,
        &EncodingKey::from_secret(state.config.jwt_secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(e.to_string()))
}

pub fn sign_refresh(state: &AppState, user_id: &str) -> AppResult<String> {
    let claims = JwtClaims {
        sub: user_id.to_string(),
        phoneNumber: None,
        role: None,
        staffRole: None,
        pages: vec![],
        username: None,
        displayName: None,
        r#type: Some("refresh".into()),
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.config.refresh_secret().as_bytes()),
    )
    .map_err(|e| AppError::Internal(e.to_string()))
}

pub fn verify_access(state: &AppState, token: &str) -> AppResult<JwtClaims> {
    decode::<JwtClaims>(
        token,
        &DecodingKey::from_secret(state.config.jwt_secret.as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| AppError::Unauthorized("Invalid or expired token".into()))
}

pub fn verify_refresh(state: &AppState, token: &str) -> AppResult<JwtClaims> {
    decode::<JwtClaims>(
        token,
        &DecodingKey::from_secret(state.config.refresh_secret().as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| AppError::Unauthorized("Invalid or expired refresh token".into()))
}

pub fn hash_refresh_token(token: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(token.as_bytes());
    hex::encode(hasher.finalize())
}

impl<S> FromRequestParts<S> for AuthUser
where
    S: Send + Sync,
    AppState: FromRef<S>,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let app = AppState::from_ref(state);
        let auth = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or_else(|| AppError::Unauthorized("Missing authorization".into()))?;
        let token = auth
            .strip_prefix("Bearer ")
            .ok_or_else(|| AppError::Unauthorized("Invalid authorization header".into()))?;
        let claims = verify_access(&app, token)?;
        Ok(AuthUser::from(claims))
    }
}

use axum::extract::FromRef;

pub fn require_admin(user: &AuthUser) -> AppResult<()> {
    if user.role.as_deref() == Some("ADMIN") && user.staff_role.is_some() {
        Ok(())
    } else {
        Err(AppError::Forbidden("Admin access required".into()))
    }
}

pub fn require_admin_page(user: &AuthUser, page: &str) -> AppResult<()> {
    require_admin(user)?;
    if user.staff_role.as_deref() == Some("SUPER_ADMIN") || user.pages.iter().any(|p| p == page) {
        Ok(())
    } else {
        Err(AppError::Forbidden(format!("Missing page access: {page}")))
    }
}

pub async fn throttle_middleware(request: Request, next: Next) -> Result<Response, StatusCode> {
    // Global throttle placeholder — per-route limits applied in handlers
    Ok(next.run(request).await)
}
