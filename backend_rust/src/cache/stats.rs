//! Cache read-through counters stored in Redis so all API replicas share one view.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use crate::redis::RedisStore;

use super::versions::Domain;

const STAT_PREFIX: &str = "gx:cache:stats:v1";
const META_KEY: &str = "gx:cache:stats:v1:meta";

const DOMAINS: [&str; 6] = [
    "hiring_master",
    "location_master",
    "service_master",
    "public_listings",
    "ephemeral",
    "user_scoped",
];

fn ratio(part: u64, total: u64) -> f64 {
    if total == 0 {
        return 0.0;
    }
    (part as f64) / (total as f64)
}

fn hash_key(domain: &str) -> String {
    format!("{STAT_PREFIX}:{domain}")
}

fn domain_slug(domain: Domain) -> &'static str {
    domain.as_str()
}

fn bump(redis: Arc<RedisStore>, domain: &str, field: &'static str) {
    let hash = hash_key(domain);
    tokio::spawn(async move {
        let _ = tokio::time::timeout(
            std::time::Duration::from_millis(100),
            async {
                let _ = redis.hincr(&hash, field, 1).await;
                if field == "requests" {
                    let now = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .map(|d| d.as_secs())
                        .unwrap_or(0);
                    let _ = redis.hset_nx(META_KEY, "started_at", &now.to_string()).await;
                }
            },
        )
        .await;
    });
}

pub fn record_read_through_request(redis: Arc<RedisStore>, domain: Domain) {
    bump(redis, domain_slug(domain), "requests");
}

pub fn record_read_through_cache_hit(redis: Arc<RedisStore>, domain: Domain) {
    bump(redis, domain_slug(domain), "cache_hits");
}

pub fn record_read_through_not_modified(redis: Arc<RedisStore>, domain: Domain) {
    bump(redis, domain_slug(domain), "not_modified");
}

pub fn record_read_through_db_load(redis: Arc<RedisStore>, domain: Domain) {
    bump(redis, domain_slug(domain), "db_loads");
}

pub fn record_read_through_fallback(redis: Arc<RedisStore>, domain: Domain) {
    bump(redis, domain_slug(domain), "fallbacks");
}

pub fn record_ephemeral_request(redis: Arc<RedisStore>) {
    bump(redis, "ephemeral", "requests");
}

pub fn record_ephemeral_cache_hit(redis: Arc<RedisStore>) {
    bump(redis, "ephemeral", "cache_hits");
}

pub fn record_ephemeral_db_load(redis: Arc<RedisStore>) {
    bump(redis, "ephemeral", "db_loads");
}

pub fn record_user_scoped_request(redis: Arc<RedisStore>) {
    bump(redis, "user_scoped", "requests");
}

pub fn record_user_scoped_cache_hit(redis: Arc<RedisStore>) {
    bump(redis, "user_scoped", "cache_hits");
}

pub fn record_user_scoped_db_load(redis: Arc<RedisStore>) {
    bump(redis, "user_scoped", "db_loads");
}

fn field_u64(map: &HashMap<String, u64>, key: &str) -> u64 {
    map.get(key).copied().unwrap_or(0)
}

fn bucket_from_map(map: HashMap<String, u64>) -> Value {
    let requests = field_u64(&map, "requests");
    let cache_hits = field_u64(&map, "cache_hits");
    let not_modified = field_u64(&map, "not_modified");
    let db_loads = field_u64(&map, "db_loads");
    let fallbacks = field_u64(&map, "fallbacks");
    let served_from_cache = cache_hits + not_modified;
    json!({
        "requests": requests,
        "cacheHits": cache_hits,
        "notModified": not_modified,
        "dbLoads": db_loads,
        "fallbacks": fallbacks,
        "servedFromCache": served_from_cache,
        "cacheHitRatio": ratio(served_from_cache, requests),
        "dbLoadRatio": ratio(db_loads, requests),
    })
}

fn merge_totals(parts: &[Value]) -> Value {
    let mut requests = 0u64;
    let mut cache_hits = 0u64;
    let mut not_modified = 0u64;
    let mut db_loads = 0u64;
    let mut fallbacks = 0u64;
    for p in parts {
        requests += p.get("requests").and_then(|v| v.as_u64()).unwrap_or(0);
        cache_hits += p.get("cacheHits").and_then(|v| v.as_u64()).unwrap_or(0);
        not_modified += p.get("notModified").and_then(|v| v.as_u64()).unwrap_or(0);
        db_loads += p.get("dbLoads").and_then(|v| v.as_u64()).unwrap_or(0);
        fallbacks += p.get("fallbacks").and_then(|v| v.as_u64()).unwrap_or(0);
    }
    let served_from_cache = cache_hits + not_modified;
    json!({
        "requests": requests,
        "cacheHits": cache_hits,
        "notModified": not_modified,
        "dbLoads": db_loads,
        "fallbacks": fallbacks,
        "servedFromCache": served_from_cache,
        "cacheHitRatio": ratio(served_from_cache, requests),
        "dbLoadRatio": ratio(db_loads, requests),
    })
}

pub async fn snapshot(redis: &RedisStore, redis_ready: bool) -> Value {
    let mut by_domain = serde_json::Map::new();
    let mut parts = Vec::new();
    for domain in DOMAINS {
        let map = redis.hgetall_u64(&hash_key(domain)).await.unwrap_or_default();
        let bucket = bucket_from_map(map);
        parts.push(bucket.clone());
        by_domain.insert(domain.to_string(), bucket);
    }
    let totals = merge_totals(&parts);
    let meta = redis.hgetall_u64(META_KEY).await.unwrap_or_default();
    let started_at = meta.get("started_at").copied().unwrap_or(0);
    let uptime_secs = if started_at > 0 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs().saturating_sub(started_at))
            .unwrap_or(0)
    } else {
        0
    };
    let note = if redis_ready {
        "Cluster-wide totals in Redis (all backend_rust replicas). Cache hit = Redis body or 304; DB load = payload loader ran."
    } else {
        "Redis unavailable — counters may be incomplete until Redis is back."
    };
    json!({
        "uptimeSecs": uptime_secs,
        "hostname": std::env::var("HOSTNAME").unwrap_or_else(|_| "gixbee-rust".into()),
        "redisReady": redis_ready,
        "aggregated": true,
        "note": note,
        "totals": totals,
        "byDomain": Value::Object(by_domain),
    })
}

pub async fn reset_all(redis: &RedisStore) -> crate::error::AppResult<()> {
    for domain in DOMAINS {
        redis.del(&hash_key(domain)).await?;
    }
    redis.del(META_KEY).await?;
    Ok(())
}
