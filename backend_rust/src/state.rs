use std::sync::Arc;

use sqlx::PgPool;

use crate::cache::CacheConfig;
use crate::config::Config;
use crate::notifications::FcmService;
use crate::realtime::RealtimeHub;
use crate::redis::RedisStore;

#[derive(Clone)]
pub struct AppState {
    pub config: Config,
    pub cache: CacheConfig,
    pub db: PgPool,
    pub redis: Arc<RedisStore>,
    pub cache_redis: Arc<RedisStore>,
    pub http: reqwest::Client,
    pub realtime: Arc<RealtimeHub>,
    pub fcm: Arc<FcmService>,
}
