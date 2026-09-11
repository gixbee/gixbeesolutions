use anyhow::{Context, Result};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use serde_json::json;
use tokio::sync::Mutex;

use crate::config::Config;

const GEO_INDEX: &str = "workers:geo";
const SKILL_INDEX_PREFIX: &str = "skill:index:";

#[derive(Debug, Clone)]
pub struct WorkerLocationSnapshot {
    pub lat: f64,
    pub lng: f64,
    pub timestamp_ms: Option<i64>,
}

pub struct RedisStore {
    ready: bool,
    /// Cheap to clone; multiplexes commands without a process-wide lock.
    client: Option<ConnectionManager>,
    allow_memory_fallback: bool,
    mem_kv: Mutex<std::collections::HashMap<String, (String, Option<std::time::Instant>)>>,
    mem_sets: Mutex<std::collections::HashMap<String, std::collections::HashSet<String>>>,
    mem_zsets: Mutex<std::collections::HashMap<String, std::collections::HashMap<String, f64>>>,
    mem_geo: Mutex<std::collections::HashMap<String, (f64, f64)>>,
}

impl RedisStore {
    #[cfg(test)]
    pub fn for_tests() -> Self {
        Self {
            ready: false, client: None, allow_memory_fallback: true,
            mem_kv: Mutex::new(Default::default()), mem_sets: Mutex::new(Default::default()),
            mem_zsets: Mutex::new(Default::default()), mem_geo: Mutex::new(Default::default()),
        }
    }

    pub async fn connect(config: &Config) -> Result<Self> {
        let client = match ConnectionManager::new(
            redis::Client::open(config.redis_url.as_str()).context("invalid redis url")?,
        )
        .await
        {
            Ok(c) => {
                tracing::info!("Redis connected successfully");
                Some(c)
            }
            Err(e) => {
                if config.redis_allow_memory_fallback {
                    tracing::warn!("Redis unreachable ({e}) — using in-memory fallback");
                    None
                } else {
                    return Err(e.into());
                }
            }
        };

        Ok(Self {
            ready: client.is_some(),
            client,
            allow_memory_fallback: config.redis_allow_memory_fallback,
            mem_kv: Mutex::new(std::collections::HashMap::new()),
            mem_sets: Mutex::new(std::collections::HashMap::new()),
            mem_zsets: Mutex::new(std::collections::HashMap::new()),
            mem_geo: Mutex::new(std::collections::HashMap::new()),
        })
    }

    fn conn(&self) -> Option<ConnectionManager> {
        self.client.clone()
    }

    fn skill_key(skill: &str) -> String {
        format!("{}{}", SKILL_INDEX_PREFIX, skill.to_lowercase().trim())
    }

    fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
        let r = 6371.0;
        let d_lat = (lat2 - lat1).to_radians();
        let d_lng = (lng2 - lng1).to_radians();
        let a = (d_lat / 2.0).sin().powi(2)
            + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
        let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
        r * c
    }

    pub fn is_ready(&self) -> bool {
        self.ready
    }

    pub async fn ping(&self) -> bool {
        let Some(mut c) = self.conn() else {
            return false;
        };
        redis::cmd("PING")
            .query_async::<String>(&mut c)
            .await
            .map(|r| r == "PONG")
            .unwrap_or(false)
    }

    fn assert_fallback(&self, op: &str) -> Result<()> {
        if self.ready || self.allow_memory_fallback {
            Ok(())
        } else {
            anyhow::bail!("Redis unavailable for {op} (in-memory fallback disabled)")
        }
    }

    pub async fn set(&self, key: &str, value: &str, ttl_secs: u64) -> Result<()> {
        self.assert_fallback("set")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.set_ex(key, value, ttl_secs).await?;
        } else {
            let mut m = self.mem_kv.lock().await;
            m.insert(
                key.to_string(),
                (
                    value.to_string(),
                    Some(std::time::Instant::now() + std::time::Duration::from_secs(ttl_secs)),
                ),
            );
        }
        Ok(())
    }

    pub async fn get(&self, key: &str) -> Result<Option<String>> {
        self.assert_fallback("get")?;
        if let Some(mut c) = self.conn() {
            let v: Option<String> = c.get(key).await?;
            Ok(v)
        } else {
            let mut m = self.mem_kv.lock().await;
            if let Some((val, exp)) = m.get(key) {
                if let Some(e) = exp {
                    if std::time::Instant::now() > *e {
                        m.remove(key);
                        return Ok(None);
                    }
                }
                Ok(Some(val.clone()))
            } else {
                Ok(None)
            }
        }
    }

    pub async fn del(&self, key: &str) -> Result<()> {
        self.assert_fallback("del")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.del(key).await?;
        } else {
            self.mem_kv.lock().await.remove(key);
        }
        Ok(())
    }

    pub async fn save_otp(&self, key: &str, otp: &str) -> Result<()> {
        self.set(key, otp, 300).await
    }

    pub async fn consume_otp(&self, key: &str) -> Result<Option<String>> {
        self.assert_fallback("consumeOtp")?;
        if let Some(mut c) = self.conn() {
            let script = redis::Script::new(
                "local v = redis.call('GET', KEYS[1]); if v then redis.call('DEL', KEYS[1]); end; return v",
            );
            let val: Option<String> = script.key(key).invoke_async(&mut c).await?;
            Ok(val)
        } else {
            let mut m = self.mem_kv.lock().await;
            if let Some((val, exp)) = m.remove(key) {
                if let Some(e) = exp {
                    if std::time::Instant::now() > e {
                        return Ok(None);
                    }
                }
                Ok(Some(val))
            } else {
                Ok(None)
            }
        }
    }

    pub async fn cache_fcm_token(&self, user_id: &str, token: &str) -> Result<()> {
        self.set(&format!("user:fcm:{user_id}"), token, 7 * 24 * 60 * 60)
            .await
    }

    pub async fn get_fcm_token(&self, user_id: &str) -> Result<Option<String>> {
        self.get(&format!("user:fcm:{user_id}")).await
    }

    pub async fn sadd(&self, key: &str, member: &str) -> Result<()> {
        self.sadd_with_ttl(key, member, None).await
    }

    pub async fn sadd_with_ttl(&self, key: &str, member: &str, ttl_secs: Option<u64>) -> Result<()> {
        self.assert_fallback("sadd")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.sadd(key, member).await?;
            if let Some(ttl) = ttl_secs {
                let _: () = c.expire(key, ttl as i64).await?;
            }
        } else {
            self.mem_sets
                .lock()
                .await
                .entry(key.to_string())
                .or_default()
                .insert(member.to_string());
        }
        Ok(())
    }

    pub async fn srem(&self, key: &str, member: &str) -> Result<()> {
        self.assert_fallback("srem")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.srem(key, member).await?;
        } else if let Some(set) = self.mem_sets.lock().await.get_mut(key) {
            set.remove(member);
        }
        Ok(())
    }

    pub async fn smembers(&self, key: &str) -> Result<Vec<String>> {
        self.assert_fallback("smembers")?;
        if let Some(mut c) = self.conn() {
            let members: Vec<String> = c.smembers(key).await?;
            Ok(members)
        } else {
            Ok(self
                .mem_sets
                .lock()
                .await
                .get(key)
                .map(|s| s.iter().cloned().collect())
                .unwrap_or_default())
        }
    }

    pub async fn zadd(&self, key: &str, score: f64, member: &str, ttl_secs: u64) -> Result<()> {
        self.assert_fallback("zadd")?;
        if let Some(mut c) = self.conn() {
            let _: () = redis::cmd("ZADD")
                .arg(key)
                .arg(score)
                .arg(member)
                .query_async(&mut c)
                .await?;
            let _: () = c.expire(key, ttl_secs as i64).await?;
        } else {
            let mut m = self.mem_zsets.lock().await;
            m.entry(key.to_string())
                .or_default()
                .insert(member.to_string(), score);
        }
        Ok(())
    }

    pub async fn zrem(&self, key: &str, member: &str) -> Result<()> {
        self.assert_fallback("zrem")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.zrem(key, member).await?;
        } else if let Some(set) = self.mem_zsets.lock().await.get_mut(key) {
            set.remove(member);
        }
        Ok(())
    }

    pub async fn zrange_rev(&self, key: &str) -> Result<Vec<String>> {
        self.assert_fallback("zrange")?;
        if let Some(mut c) = self.conn() {
            let members: Vec<String> = redis::cmd("ZREVRANGE")
                .arg(key)
                .arg(0)
                .arg(-1)
                .query_async(&mut c)
                .await?;
            Ok(members)
        } else {
            let mut members: Vec<(String, f64)> = self
                .mem_zsets
                .lock()
                .await
                .get(key)
                .map(|m| m.iter().map(|(k, v)| (k.clone(), *v)).collect())
                .unwrap_or_default();
            members.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
            Ok(members.into_iter().map(|(k, _)| k).collect())
        }
    }

    pub async fn add_pending_booking(&self, worker_id: &str, booking_id: &str) -> Result<()> {
        let key = format!("worker:pending:{worker_id}");
        self.zadd(&key, chrono::Utc::now().timestamp_millis() as f64, booking_id, 120)
            .await
    }

    pub async fn remove_pending_booking(&self, worker_id: &str, booking_id: &str) -> Result<()> {
        self.zrem(&format!("worker:pending:{worker_id}"), booking_id)
            .await
    }

    pub async fn get_pending_booking_ids(&self, worker_id: &str) -> Result<Vec<String>> {
        self.zrange_rev(&format!("worker:pending:{worker_id}")).await
    }

    pub async fn get_rejected_workers_for_job(
        &self,
        customer_id: &str,
        skill: &str,
    ) -> Result<Vec<String>> {
        self.smembers(&format!("rejected:{}:{}", customer_id, skill.to_lowercase()))
            .await
    }

    pub async fn mark_worker_rejected_job(
        &self,
        customer_id: &str,
        skill: &str,
        worker_id: &str,
    ) -> Result<()> {
        self.sadd_with_ttl(
            &format!("rejected:{}:{}", customer_id, skill.to_lowercase()),
            worker_id,
            Some(900),
        )
        .await
    }

    pub async fn cache_booking_status(
        &self,
        booking_id: &str,
        patch: &serde_json::Value,
    ) -> Result<()> {
        let key = format!("booking:status:{booking_id}");
        let existing = self
            .get(&key)
            .await?
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
            .unwrap_or(json!({}));
        let mut merged = existing;
        if let Some(obj) = patch.as_object() {
            for (k, v) in obj {
                if v.is_null() {
                    if let Some(m) = merged.as_object_mut() {
                        m.remove(k);
                    }
                } else {
                    merged[k] = v.clone();
                }
            }
        }
        self.set(&key, &merged.to_string(), 24 * 60 * 60).await
    }

    pub async fn update_worker_location(
        &self,
        user_id: &str,
        lat: f64,
        lng: f64,
    ) -> Result<()> {
        let payload = serde_json::json!({
            "lat": lat,
            "lng": lng,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        });
        self.set(
            &format!("worker:location:{user_id}"),
            &payload.to_string(),
            3600,
        )
        .await?;
        self.geo_add(user_id, lat, lng).await
    }

    pub async fn get_worker_location(&self, user_id: &str) -> Result<Option<(f64, f64)>> {
        Ok(self
            .get_worker_location_detail(user_id)
            .await?
            .map(|loc| (loc.lat, loc.lng)))
    }

    pub async fn get_worker_location_detail(
        &self,
        user_id: &str,
    ) -> Result<Option<WorkerLocationSnapshot>> {
        for key in [
            format!("worker:location:{user_id}"),
            format!("worker:loc:{user_id}"),
        ] {
            if let Some(raw) = self.get(&key).await? {
                if let Ok(v) = serde_json::from_str::<serde_json::Value>(&raw) {
                    let lat = v.get("lat").and_then(|x| x.as_f64());
                    let lng = v.get("lng").and_then(|x| x.as_f64());
                    if let (Some(lat), Some(lng)) = (lat, lng) {
                        let timestamp_ms = v.get("timestamp").and_then(|ts| {
                            ts.as_str()
                                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                                .map(|dt| dt.timestamp_millis())
                                .or_else(|| ts.as_i64())
                        });
                        return Ok(Some(WorkerLocationSnapshot {
                            lat,
                            lng,
                            timestamp_ms,
                        }));
                    }
                }
            }
        }
        Ok(None)
    }

    pub async fn get_worker_status(&self, user_id: &str) -> Result<String> {
        Ok(self
            .get(&format!("worker:status:{user_id}"))
            .await?
            .unwrap_or_else(|| "available".to_string()))
    }

    pub async fn set_worker_status(&self, user_id: &str, status: &str) -> Result<()> {
        self.set(&format!("worker:status:{user_id}"), status, 3600)
            .await
    }

    pub async fn geo_add(&self, member: &str, lat: f64, lng: f64) -> Result<()> {
        self.assert_fallback("geoAdd")?;
        if let Some(mut c) = self.conn() {
            let _: () = redis::cmd("GEOADD")
                .arg(GEO_INDEX)
                .arg(lng)
                .arg(lat)
                .arg(member)
                .query_async(&mut c)
                .await?;
        } else {
            self.mem_geo
                .lock()
                .await
                .insert(member.to_string(), (lat, lng));
        }
        Ok(())
    }

    pub async fn geo_rem(&self, member: &str) -> Result<()> {
        self.assert_fallback("geoRem")?;
        if let Some(mut c) = self.conn() {
            let _: () = c.zrem(GEO_INDEX, member).await?;
        } else {
            self.mem_geo.lock().await.remove(member);
        }
        Ok(())
    }

    /// Returns nearby worker user IDs within `radius_km`, or `None` when the geo
    /// index is unavailable (cold Redis, command failure).
    pub async fn search_nearby_worker_ids(
        &self,
        lat: f64,
        lng: f64,
        radius_km: f64,
    ) -> Result<Option<Vec<String>>> {
        self.assert_fallback("geoSearch")?;
        if let Some(mut c) = self.conn() {
            let members: Result<Vec<String>, redis::RedisError> = redis::cmd("GEOSEARCH")
                .arg(GEO_INDEX)
                .arg("FROMLONLAT")
                .arg(lng)
                .arg(lat)
                .arg("BYRADIUS")
                .arg(radius_km)
                .arg("km")
                .query_async(&mut c)
                .await;
            match members {
                Ok(ids) => Ok(Some(ids)),
                Err(e) => {
                    tracing::warn!("Redis GEOSEARCH failed: {e}");
                    Ok(None)
                }
            }
        } else if self.allow_memory_fallback {
            let result: Vec<String> = self
                .mem_geo
                .lock()
                .await
                .iter()
                .filter(|(_, (wlat, wlng))| Self::haversine_km(lat, lng, *wlat, *wlng) <= radius_km)
                .map(|(id, _)| id.clone())
                .collect();
            Ok(Some(result))
        } else {
            Ok(None)
        }
    }

    pub async fn index_worker_skills(&self, user_id: &str, skills: &[String]) -> Result<()> {
        for skill in skills {
            let key = Self::skill_key(skill);
            self.sadd_with_ttl(&key, user_id, Some(24 * 60 * 60)).await?;
        }
        Ok(())
    }

    pub async fn unindex_worker_skills(&self, user_id: &str, skills: &[String]) -> Result<()> {
        for skill in skills {
            self.srem(&Self::skill_key(skill), user_id).await?;
        }
        Ok(())
    }

    pub async fn get_worker_ids_by_skill(&self, skill: &str) -> Result<Vec<String>> {
        self.smembers(&Self::skill_key(skill)).await
    }

    pub async fn clear_worker_live_state(&self, user_id: &str, skills: &[String]) -> Result<()> {
        let _ = self.del(&format!("worker:location:{user_id}")).await;
        let _ = self.del(&format!("worker:loc:{user_id}")).await;
        let _ = self.del(&format!("worker:status:{user_id}")).await;
        let _ = self.del(&format!("worker:snapshot:{user_id}")).await;
        self.unindex_worker_skills(user_id, skills).await?;
        self.geo_rem(user_id).await
    }

    pub async fn acquire_lock(&self, key: &str, ttl_secs: u64) -> Result<bool> {
        self.assert_fallback("acquireLock")?;
        if let Some(mut c) = self.conn() {
            let ok: Option<String> = redis::cmd("SET")
                .arg(key)
                .arg("1")
                .arg("NX")
                .arg("EX")
                .arg(ttl_secs)
                .query_async(&mut c)
                .await?;
            Ok(ok.is_some())
        } else {
            let mut m = self.mem_kv.lock().await;
            if m.contains_key(key) {
                return Ok(false);
            }
            m.insert(
                key.to_string(),
                (
                    "1".to_string(),
                    Some(std::time::Instant::now() + std::time::Duration::from_secs(ttl_secs)),
                ),
            );
            Ok(true)
        }
    }
}
