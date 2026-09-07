use std::env;

use anyhow::{anyhow, Context, Result};

#[derive(Clone, Debug)]
pub struct Config {
    pub port: u16,
    pub node_env: String,
    pub is_production: bool,
    pub database_url: String,
    pub redis_url: String,
    pub redis_allow_memory_fallback: bool,
    pub jwt_secret: String,
    pub admin_username: Option<String>,
    pub admin_password: Option<String>,
    pub allow_otp_echo: bool,
    pub msg91_auth_key: Option<String>,
    pub msg91_template_id: Option<String>,
    pub msg91_sender_id: String,
    pub razorpay_key_id: Option<String>,
    pub razorpay_key_secret: Option<String>,
    pub razorpay_webhook_secret: Option<String>,
    pub firebase_key_path: Option<String>,
    pub firebase_project_id: Option<String>,
    pub firebase_client_email: Option<String>,
    pub firebase_private_key: Option<String>,
    pub aadhaar_client_id: Option<String>,
    pub aadhaar_client_secret: Option<String>,
    pub aadhaar_api_base: String,
    pub log_retention_days: u32,
    pub uploads_dir: String,
    pub webrtc_stun_urls: String,
    pub webrtc_turn_urls: Option<String>,
    pub webrtc_turn_username: Option<String>,
    pub webrtc_turn_credential: Option<String>,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        dotenvy::dotenv().ok();

        let node_env = env::var("NODE_ENV").unwrap_or_else(|_| "development".into());
        let is_production = node_env == "production";

        let database_url = env::var("DATABASE_URL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| {
            let host = env::var("DATABASE_HOST").unwrap_or_else(|_| "postgres".into());
            let port = env::var("DATABASE_PORT").unwrap_or_else(|_| "5432".into());
            let user = env::var("DATABASE_USER").unwrap_or_else(|_| "postgres".into());
            let password = env::var("DATABASE_PASSWORD").unwrap_or_else(|_| "gixbee123".into());
            let name = env::var("DATABASE_NAME").unwrap_or_else(|_| "gixbee_db".into());
            format!("postgres://{user}:{password}@{host}:{port}/{name}")
        });

        let redis_url = env::var("REDIS_URL").ok().filter(|s| !s.is_empty()).unwrap_or_else(|| {
            let host = env::var("REDIS_HOST").unwrap_or_else(|_| "redis".into());
            let port = env::var("REDIS_PORT").unwrap_or_else(|_| "6379".into());
            let password = env::var("REDIS_PASSWORD").ok().filter(|s| !s.is_empty());
            match password {
                Some(p) => format!("redis://:{p}@{host}:{port}"),
                None => format!("redis://{host}:{port}"),
            }
        });

        Ok(Self {
            port: env::var("PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(3000),
            node_env,
            is_production,
            database_url,
            redis_url,
            redis_allow_memory_fallback: env::var("REDIS_ALLOW_MEMORY_FALLBACK")
                .map(|v| v == "true")
                .unwrap_or(!is_production),
            jwt_secret: env::var("JWT_SECRET").unwrap_or_else(|_| "super-secret-key-for-gixbee".into()),
            admin_username: env::var("ADMIN_USERNAME").ok().filter(|s| !s.is_empty()),
            admin_password: env::var("ADMIN_PASSWORD").ok().filter(|s| !s.is_empty()),
            allow_otp_echo: env::var("ALLOW_OTP_ECHO").map(|v| v == "true").unwrap_or(false),
            msg91_auth_key: env::var("MSG91_AUTH_KEY").ok().filter(|s| !s.is_empty()),
            msg91_template_id: env::var("MSG91_TEMPLATE_ID").ok().filter(|s| !s.is_empty()),
            msg91_sender_id: env::var("MSG91_SENDER_ID").unwrap_or_else(|_| "GIXBEE".into()),
            razorpay_key_id: env::var("RAZORPAY_KEY_ID").ok().filter(|s| !s.is_empty()),
            razorpay_key_secret: env::var("RAZORPAY_KEY_SECRET").ok().filter(|s| !s.is_empty()),
            razorpay_webhook_secret: env::var("RAZORPAY_WEBHOOK_SECRET").ok().filter(|s| !s.is_empty()),
            firebase_key_path: env::var("FIREBASE_KEY_PATH").ok().filter(|s| !s.is_empty()),
            firebase_project_id: env::var("FIREBASE_PROJECT_ID").ok().filter(|s| !s.is_empty()),
            firebase_client_email: env::var("FIREBASE_CLIENT_EMAIL").ok().filter(|s| !s.is_empty()),
            firebase_private_key: env::var("FIREBASE_PRIVATE_KEY").ok().filter(|s| !s.is_empty()),
            aadhaar_client_id: env::var("AADHAAR_CLIENT_ID").ok().filter(|s| !s.is_empty()),
            aadhaar_client_secret: env::var("AADHAAR_CLIENT_SECRET").ok().filter(|s| !s.is_empty()),
            aadhaar_api_base: env::var("AADHAAR_API_BASE")
                .unwrap_or_else(|_| "https://sandbox.surepass.app".into()),
            log_retention_days: env::var("LOG_RETENTION_DAYS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(30),
            uploads_dir: env::var("UPLOADS_DIR").unwrap_or_else(|_| "./uploads".into()),
            webrtc_stun_urls: env::var("WEBRTC_STUN_URLS")
                .unwrap_or_else(|_| "stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302".into()),
            webrtc_turn_urls: env::var("WEBRTC_TURN_URLS").ok().filter(|s| !s.is_empty()),
            webrtc_turn_username: env::var("WEBRTC_TURN_USERNAME").ok().filter(|s| !s.is_empty()),
            webrtc_turn_credential: env::var("WEBRTC_TURN_CREDENTIAL").ok().filter(|s| !s.is_empty()),
        })
    }

    pub fn refresh_secret(&self) -> String {
        format!("{}-refresh", self.jwt_secret)
    }
}

pub fn is_real_secret(value: Option<&str>) -> bool {
    let value = match value.map(str::trim).filter(|v| !v.is_empty()) {
        Some(v) => v,
        None => return false,
    };
    if value.len() < 4 {
        return false;
    }
    let lower = value.to_lowercase();
    !lower.starts_with("placeholder")
        && !lower.starts_with("your-")
        && !lower.starts_with("your_")
        && lower != "changeme"
        && !lower.starts_with("replace-with")
        && lower != "super-secret-key-for-gixbee"
}

pub fn assert_production_secrets(config: &Config) -> Result<()> {
    if !config.is_production {
        return Ok(());
    }

    let mut problems = Vec::new();
    let weak_jwt = ["super-secret-key-for-gixbee", "secret", "changeme", ""];
    if weak_jwt.contains(&config.jwt_secret.as_str()) || config.jwt_secret.len() < 32 {
        problems.push("JWT_SECRET is missing, default, or shorter than 32 chars");
    }
    if config.admin_username.as_deref().map(|u| u.is_empty() || u == "admin").unwrap_or(true) {
        problems.push("ADMIN_USERNAME is missing or the default \"admin\"");
    }
    let pass = config.admin_password.as_deref().unwrap_or("");
    if pass.is_empty() || pass == "admin" || pass.len() < 12 {
        problems.push("ADMIN_PASSWORD is missing, default, or shorter than 12 chars");
    }
    if config.allow_otp_echo {
        problems.push("ALLOW_OTP_ECHO=true would return login OTPs to callers");
    }
    if !is_real_secret(config.msg91_auth_key.as_deref())
        || !is_real_secret(config.msg91_template_id.as_deref())
    {
        problems.push("MSG91_AUTH_KEY / MSG91_TEMPLATE_ID missing — login OTP SMS will not deliver");
    }
    if !is_real_secret(config.razorpay_key_id.as_deref())
        || !is_real_secret(config.razorpay_key_secret.as_deref())
    {
        problems.push(
            "RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET missing or placeholder — period fee / late-cancel payments disabled",
        );
    }

    if !problems.is_empty() {
        eprintln!("\n[FATAL] Refusing to start in production with insecure config:");
        for p in &problems {
            eprintln!("  - {}", p);
        }
        eprintln!("Rotate these values and restart.\n");
        return Err(anyhow!("insecure production configuration"));
    }
    Ok(())
}

pub async fn connect_db(database_url: &str) -> Result<sqlx::PgPool> {
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(50)
        .acquire_timeout(std::time::Duration::from_secs(10))
        .connect(database_url)
        .await
        .context("failed to connect to postgres")?;
    Ok(pool)
}
