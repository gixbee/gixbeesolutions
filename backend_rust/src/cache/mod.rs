//! Redis cache-aside for read-heavy public masters and listings.
//! Correctness locks (OTP, rate limits) stay on [`crate::redis::RedisStore`] directly.

use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use serde_json::Value;
use tokio::sync::Mutex;

use crate::error::AppResult;
use crate::redis::RedisStore;
use crate::state::AppState;

pub mod http;
pub mod stats;
pub mod versions;

pub use versions::{bump_in_tx, bump_now, commit_bump_tx, current_version, Domain};

const REDIS_OP_TIMEOUT: Duration = Duration::from_millis(250);
const COALESCE_WAIT: Duration = Duration::from_millis(80);
const MAX_COALESCE_ROUNDS: u32 = 12;

lazy_static::lazy_static! {
    static ref INFLIGHT: Mutex<std::collections::HashSet<String>> =
        Mutex::new(std::collections::HashSet::new());
}

#[derive(Clone)]
pub struct CacheConfig {
    pub hiring_master_ttl_secs: u64,
    pub service_master_ttl_secs: u64,
    pub location_search_ttl_secs: u64,
    pub location_empty_ttl_secs: u64,
    pub public_listing_ttl_secs: u64,
    pub hiring_estimate_ttl_secs: u64,
}

impl CacheConfig {
    pub fn from_env() -> Self {
        let service_hours = env_u64("CACHE_SERVICE_MASTER_TTL_HOURS", 6).clamp(1, 24);
        let listing_minutes = env_u64("CACHE_PUBLIC_LISTING_TTL_MINUTES", 2).clamp(1, 5);
        Self {
            hiring_master_ttl_secs: env_u64("CACHE_HIRING_MASTER_TTL_SECS", 86_400),
            service_master_ttl_secs: service_hours * 3600,
            location_search_ttl_secs: env_u64("CACHE_LOCATION_SEARCH_TTL_SECS", 86_400),
            location_empty_ttl_secs: env_u64("CACHE_LOCATION_EMPTY_TTL_SECS", 300),
            public_listing_ttl_secs: listing_minutes * 60,
            hiring_estimate_ttl_secs: env_u64("CACHE_HIRING_ESTIMATE_TTL_SECS", 20).clamp(15, 30),
        }
    }
}

fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CacheOutcome {
    Hit,
    Miss,
    Fallback,
}

#[derive(Debug)]
pub struct CachedBody {
    pub json: Value,
    pub etag: String,
    pub outcome: CacheOutcome,
}

/// TTL with ±10% jitter to spread expirations.
pub fn ttl_with_jitter(base_secs: u64) -> u64 {
    if base_secs == 0 {
        return 0;
    }
    let jitter = (base_secs / 10).max(1);
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64)
        .unwrap_or(0);
    base_secs + (seed % (jitter * 2 + 1)).saturating_sub(jitter)
}

fn envelope(version: i64, body: &Value) -> Value {
    serde_json::json!({ "v": version, "body": body })
}

fn parse_envelope(raw: &str) -> Option<(i64, Value)> {
    let parsed: Value = serde_json::from_str(raw).ok()?;
    let version = parsed.get("v")?.as_i64()?;
    let body = parsed.get("body")?.clone();
    Some((version, body))
}

async fn redis_get(redis: &RedisStore, key: &str) -> Option<String> {
    match tokio::time::timeout(REDIS_OP_TIMEOUT, redis.get(key)).await {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => {
            tracing::warn!(target: "cache", op = "get", err = %e, "redis read failed");
            None
        }
        Err(_) => {
            tracing::warn!(target: "cache", op = "get", "redis read timed out");
            None
        }
    }
}

async fn redis_set(redis: &RedisStore, key: &str, value: &str, ttl: u64) -> bool {
    match tokio::time::timeout(REDIS_OP_TIMEOUT, redis.set(key, value, ttl_with_jitter(ttl))).await
    {
        Ok(Ok(())) => true,
        Ok(Err(e)) => {
            tracing::warn!(target: "cache", op = "set", err = %e, "redis write failed");
            false
        }
        Err(_) => {
            tracing::warn!(target: "cache", op = "set", "redis write timed out");
            false
        }
    }
}

fn etag_for(domain: Domain, version: i64, key_suffix: &str) -> String {
    format!("\"{}-{}-{}\"", domain.as_str(), version, fnv1a64(key_suffix))
}

pub fn cache_key_hash(parts: &[&str]) -> u64 {
    fnv1a64(&parts.join("\x1f"))
}

fn fnv1a64(text: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for b in text.bytes() {
        hash ^= u64::from(b);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

pub fn normalize_search_query(raw: &str) -> String {
    raw.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

type LoaderFut<'a> = Pin<Box<dyn Future<Output = AppResult<Value>> + Send + 'a>>;

pub async fn read_through<'a, F>(
    state: &'a AppState,
    domain: Domain,
    key_suffix: &str,
    ttl_secs: u64,
    empty_short_ttl: Option<u64>,
    if_none_match: Option<&str>,
    loader: F,
) -> AppResult<CachedBody>
where
    F: FnOnce() -> LoaderFut<'a>,
{
    stats::record_read_through_request(state.cache_redis.clone(), domain);
    let version = current_version(&state.db, domain).await?;
    let redis_key = format!("gx:v1:{}:{}:{}", domain.as_str(), version, fnv1a64(key_suffix));
    let etag = etag_for(domain, version, key_suffix);

    if let Some(client) = if_none_match {
        if client.trim_matches('"') == etag.trim_matches('"') {
            stats::record_read_through_not_modified(state.cache_redis.clone(), domain);
            tracing::debug!(target: "cache", domain = domain.as_str(), outcome = "not_modified");
            return Ok(CachedBody {
                json: Value::Null,
                etag,
                outcome: CacheOutcome::Hit,
            });
        }
    }

    if let Some(raw) = redis_get(&state.cache_redis, &redis_key).await {
        if let Some((cached_v, body)) = parse_envelope(&raw) {
            if cached_v == version {
                stats::record_read_through_cache_hit(state.cache_redis.clone(), domain);
                tracing::debug!(target: "cache", domain = domain.as_str(), outcome = "hit");
                return Ok(CachedBody {
                    json: body,
                    etag,
                    outcome: CacheOutcome::Hit,
                });
            }
            tracing::debug!(target: "cache", domain = domain.as_str(), outcome = "stale_version");
        }
    }

    let lock_key = format!("lock:{redis_key}");
    let mut waited = 0u32;
    let mut redis_coalesce = true;
    loop {
        if !redis_coalesce {
            break;
        }
        match tokio::time::timeout(
            REDIS_OP_TIMEOUT,
            state.cache_redis.acquire_lock(&lock_key, 8),
        )
        .await
        {
            Ok(Ok(true)) => break,
            Ok(Ok(false)) => {}
            Ok(Err(e)) => {
                tracing::warn!(target: "cache", op = "lock", err = %e, "redis lock failed");
                redis_coalesce = false;
                break;
            }
            Err(_) => {
                tracing::warn!(target: "cache", op = "lock", "redis lock timed out");
                redis_coalesce = false;
                break;
            }
        }
        if waited >= MAX_COALESCE_ROUNDS {
            break;
        }
        waited += 1;
        tokio::time::sleep(COALESCE_WAIT).await;
        if let Some(raw) = redis_get(&state.cache_redis, &redis_key).await {
            if let Some((cached_v, body)) = parse_envelope(&raw) {
                if cached_v == version {
                    stats::record_read_through_cache_hit(state.cache_redis.clone(), domain);
                    tracing::debug!(target: "cache", domain = domain.as_str(), outcome = "hit_coalesced");
                    return Ok(CachedBody {
                        json: body,
                        etag,
                        outcome: CacheOutcome::Hit,
                    });
                }
            }
        }
    }

    {
        let mut guard = INFLIGHT.lock().await;
        if !guard.insert(redis_key.clone()) {
            // Another task on this replica is loading the same key — fall through to DB.
        }
    }

    let load_version = version;
    stats::record_read_through_db_load(state.cache_redis.clone(), domain);
    let body = loader().await?;
    let _ = INFLIGHT.lock().await.remove(&redis_key);

    let fresh_version = current_version(&state.db, domain).await.unwrap_or(load_version);
    if fresh_version != load_version {
        tracing::debug!(
            target: "cache",
            domain = domain.as_str(),
            outcome = "version_changed_during_load"
        );
        // Return loaded body without a reusable validator; do not cache under a new ETag.
        stats::record_read_through_fallback(state.cache_redis.clone(), domain);
        return Ok(CachedBody {
            json: body,
            etag: String::new(),
            outcome: CacheOutcome::Fallback,
        });
    }

    let is_empty = body
        .get("items")
        .and_then(|v| v.as_array())
        .is_some_and(|a| a.is_empty())
        || body.as_array().is_some_and(|a| a.is_empty());
    let ttl = if is_empty {
        empty_short_ttl.unwrap_or(ttl_secs.min(300))
    } else {
        ttl_secs
    };

    let payload = envelope(load_version, &body);
    if let Ok(text) = serde_json::to_string(&payload) {
        if text.len() <= 512_000 {
            let _ = redis_set(&state.cache_redis, &redis_key, &text, ttl).await;
        } else {
            tracing::warn!(target: "cache", domain = domain.as_str(), "payload too large to cache");
        }
    }

    tracing::debug!(target: "cache", domain = domain.as_str(), outcome = "miss");
    Ok(CachedBody {
        json: body,
        etag,
        outcome: CacheOutcome::Miss,
    })
}

pub async fn read_through_user_scoped<'a, F>(
    state: &'a AppState,
    user_id: &str,
    key_suffix: &str,
    ttl_secs: u64,
    loader: F,
) -> AppResult<Value>
where
    F: FnOnce() -> LoaderFut<'a>,
{
    stats::record_user_scoped_request(state.cache_redis.clone());
    let redis_key = format!("gx:v1:user:{user_id}:{}", fnv1a64(key_suffix));
    if let Some(raw) = redis_get(&state.cache_redis, &redis_key).await {
        if let Ok(v) = serde_json::from_str::<Value>(&raw) {
            stats::record_user_scoped_cache_hit(state.cache_redis.clone());
            return Ok(v);
        }
    }
    stats::record_user_scoped_db_load(state.cache_redis.clone());
    let body = loader().await?;
    if let Ok(text) = serde_json::to_string(&body) {
        let _ = redis_set(&state.cache_redis, &redis_key, &text, ttl_secs).await;
    }
    Ok(body)
}

pub async fn invalidate_user_scope(redis: &RedisStore, user_id: &str) -> AppResult<()> {
    let _ = redis.del(&format!("gx:v1:user:{user_id}:prefs")).await;
    Ok(())
}

/// Short-lived display cache (e.g. hiring estimate). Not used for authorization.
pub async fn read_ephemeral<'a, F>(
    redis: std::sync::Arc<RedisStore>,
    key: &str,
    ttl_secs: u64,
    loader: F,
) -> AppResult<Value>
where
    F: FnOnce() -> LoaderFut<'a>,
{
    stats::record_ephemeral_request(redis.clone());
    if let Some(raw) = redis_get(redis.as_ref(), key).await {
        if let Ok(v) = serde_json::from_str::<Value>(&raw) {
            stats::record_ephemeral_cache_hit(redis.clone());
            tracing::debug!(target: "cache", op = "ephemeral_hit");
            return Ok(v);
        }
    }
    stats::record_ephemeral_db_load(redis.clone());
    let body = loader().await?;
    if let Ok(text) = serde_json::to_string(&body) {
        let _ = redis_set(redis.as_ref(), key, &text, ttl_secs).await;
    }
    Ok(body)
}
