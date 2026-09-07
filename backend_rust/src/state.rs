use std::sync::Arc;

use sqlx::PgPool;

use crate::config::Config;
use crate::redis::RedisStore;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub db: PgPool,
    pub redis: Arc<RedisStore>,
    pub http: reqwest::Client,
}
