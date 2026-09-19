use std::sync::Arc;
use std::time::{Duration, Instant};

use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use tokio::sync::Mutex;
use tracing::{error, warn};
use uuid::Uuid;

use crate::config::Config;
use crate::state::AppState;

const FCM_SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";

#[derive(Clone)]
struct FcmCredentials {
    project_id: String,
    client_email: String,
    private_key: EncodingKey,
}

#[derive(Clone)]
pub struct FcmService {
    credentials: Option<FcmCredentials>,
    http: reqwest::Client,
    token_cache: Arc<Mutex<Option<(String, Instant)>>>,
}

impl FcmService {
    pub fn from_config(config: &Config, http: reqwest::Client) -> Self {
        let credentials = load_credentials(config);
        if credentials.is_none() {
            warn!("Firebase credentials missing — push notifications disabled");
        }
        Self {
            credentials,
            http,
            token_cache: Arc::new(Mutex::new(None)),
        }
    }

    pub fn is_ready(&self) -> bool {
        self.credentials.is_some()
    }

    pub fn diagnostics(&self, config: &Config) -> Value {
        json!({
            "firebaseInitialized": self.is_ready(),
            "credentials": {
                "hasProjectId": config.firebase_project_id.is_some(),
                "hasClientEmail": config.firebase_client_email.is_some(),
                "hasPrivateKey": config.firebase_private_key.is_some(),
                "projectId": config.firebase_project_id.as_deref().unwrap_or("(not set)"),
            }
        })
    }

    pub async fn send_to_user(
        &self,
        state: &AppState,
        user_id: &str,
        title: &str,
        body: &str,
        data: Option<&[(&str, &str)]>,
    ) -> bool {
        let token = match resolve_fcm_token(state, user_id).await {
            Some(t) => t,
            None => {
                warn!("[FCM] No token for user {}", user_id);
                return false;
            }
        };
        self.send_to_device(&token, title, body, data).await
    }

    pub async fn send_to_users(
        &self,
        state: &AppState,
        user_ids: &[String],
        title: &str,
        body: &str,
        data: Option<&[(&str, &str)]>,
    ) {
        for uid in user_ids {
            self.send_to_user(state, uid, title, body, data).await;
        }
    }

    pub async fn test_push(&self, state: &AppState, user_id: &str) -> Value {
        let mut steps: Vec<String> = Vec::new();
        let token = match resolve_fcm_token(state, user_id).await {
            Some(t) => {
                steps.push(format!(
                    "token found ({}...)",
                    t.chars().take(20).collect::<String>()
                ));
                t
            }
            None => {
                steps.push("no FCM token — device must call PATCH /auth/fcm-token".into());
                return json!({
                    "success": false,
                    "userId": user_id,
                    "steps": steps,
                    "message": "No FCM token saved for this user",
                });
            }
        };

        if !self.is_ready() {
            steps.push("Firebase not configured".into());
            return json!({
                "success": false,
                "userId": user_id,
                "steps": steps,
                "message": "Firebase credentials missing",
            });
        }

        let ok = self
            .send_to_device(
                &token,
                "FCM Test",
                "If you see this, push notifications are working!",
                Some(&[("type", "test_push")]),
            )
            .await;
        steps.push(if ok {
            "push accepted by Firebase".into()
        } else {
            "push failed".into()
        });
        json!({
            "success": ok,
            "userId": user_id,
            "steps": steps,
            "message": if ok { "Push sent successfully" } else { "Push failed" },
        })
    }

    async fn send_to_device(
        &self,
        fcm_token: &str,
        title: &str,
        body: &str,
        data: Option<&[(&str, &str)]>,
    ) -> bool {
        let creds = match &self.credentials {
            Some(c) => c,
            None => return false,
        };
        let access = match self.access_token(creds).await {
            Ok(t) => t,
            Err(e) => {
                error!("[FCM] token fetch failed: {e}");
                return false;
            }
        };

        let mut data_map = serde_json::Map::new();
        if let Some(pairs) = data {
            for (k, v) in pairs {
                data_map.insert(k.to_string(), Value::String(v.to_string()));
            }
        }

        let url = format!(
            "https://fcm.googleapis.com/v1/projects/{}/messages:send",
            creds.project_id
        );
        let payload = json!({
            "message": {
                "token": fcm_token,
                "notification": { "title": title, "body": body },
                "data": data_map,
                "android": {
                    "priority": "HIGH",
                    "notification": {
                        "channel_id": "gixbee_high_importance_v2",
                        "sound": "gixbee_alert",
                        "notification_priority": "PRIORITY_MAX"
                    }
                },
                "apns": {
                    "headers": { "apns-priority": "10" },
                    "payload": {
                        "aps": {
                            "sound": "gixbee_alert.wav",
                            "badge": 1,
                            "content-available": 1
                        }
                    }
                }
            }
        });

        let resp = self
            .http
            .post(&url)
            .bearer_auth(access)
            .json(&payload)
            .send()
            .await;
        match resp {
            Ok(r) if r.status().is_success() => true,
            Ok(r) => {
                let status = r.status();
                let body = r.text().await.unwrap_or_default();
                error!("[FCM] send failed: {} {}", status, body);
                false
            }
            Err(e) => {
                error!("[FCM] HTTP error: {e}");
                false
            }
        }
    }

    async fn access_token(&self, creds: &FcmCredentials) -> Result<String, String> {
        {
            let guard = self.token_cache.lock().await;
            if let Some((token, exp)) = guard.as_ref() {
                if Instant::now() < *exp {
                    return Ok(token.clone());
                }
            }
        }

        let now = chrono::Utc::now().timestamp();
        let claims = json!({
            "iss": creds.client_email,
            "scope": FCM_SCOPE,
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
        });
        let jwt = encode(
            &Header::new(Algorithm::RS256),
            &claims,
            &creds.private_key,
        )
        .map_err(|e| e.to_string())?;

        let resp = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &jwt),
            ])
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            return Err(resp.text().await.unwrap_or_default());
        }
        let body: TokenResponse = resp.json().await.map_err(|e| e.to_string())?;
        let expires = Instant::now() + Duration::from_secs(body.expires_in.saturating_sub(60));
        let mut guard = self.token_cache.lock().await;
        *guard = Some((body.access_token.clone(), expires));
        Ok(body.access_token)
    }
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

#[derive(Deserialize)]
struct ServiceAccountJson {
    project_id: String,
    client_email: String,
    private_key: String,
}

fn load_credentials(config: &Config) -> Option<FcmCredentials> {
    if let Some(path) = &config.firebase_key_path {
        match std::fs::read_to_string(path) {
            Ok(raw) => match serde_json::from_str::<ServiceAccountJson>(&raw) {
                Ok(sa) => {
                    if let Some(creds) =
                        build_credentials(&sa.project_id, &sa.client_email, &sa.private_key)
                    {
                        return Some(creds);
                    }
                    warn!("Firebase key file at {path} has an unreadable private key");
                }
                Err(e) => warn!("Firebase key file at {path} is not a service account JSON: {e}"),
            },
            Err(e) => warn!("Firebase key file at {path} could not be read: {e}"),
        }
    }
    match (
        config.firebase_project_id.as_deref(),
        config.firebase_client_email.as_deref(),
        config.firebase_private_key.as_deref(),
    ) {
        (Some(project_id), Some(client_email), Some(private_key)) => {
            if let Some(creds) = build_credentials(project_id, client_email, private_key) {
                return Some(creds);
            }
            warn!("FIREBASE_PRIVATE_KEY env var is not a valid PEM key");
        }
        _ => {}
    }
    None
}

fn build_credentials(
    project_id: &str,
    client_email: &str,
    private_key: &str,
) -> Option<FcmCredentials> {
    if project_id.trim().is_empty() || project_id.contains("placeholder") {
        warn!("Firebase project_id is missing or a placeholder");
        return None;
    }
    let pem = private_key.replace("\\n", "\n");
    let key = match EncodingKey::from_rsa_pem(pem.as_bytes()) {
        Ok(k) => k,
        Err(e) => {
            warn!("Firebase private key PEM parse failed: {e}");
            return None;
        }
    };
    Some(FcmCredentials {
        project_id: project_id.to_string(),
        client_email: client_email.to_string(),
        private_key: key,
    })
}

async fn resolve_fcm_token(state: &AppState, user_id: &str) -> Option<String> {
    if let Ok(Some(t)) = state.redis.get_fcm_token(user_id).await {
        return Some(t);
    }
    let uid = Uuid::parse_str(user_id).ok()?;
    let row = sqlx::query(r#"SELECT "fcmToken" FROM users WHERE id = $1"#)
        .bind(uid)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten()?;
    let token: Option<String> = row.try_get("fcmToken").ok().flatten();
    if let Some(t) = token {
        let _ = state.redis.cache_fcm_token(user_id, &t).await;
        return Some(t);
    }
    None
}
