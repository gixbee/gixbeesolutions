use anyhow::{Context, Result};
use redis::aio::ConnectionManager;
use redis::AsyncCommands;
use tokio::sync::Mutex;

use crate::config::Config;

pub struct RedisStore {
    ready: bool,
    client: Mutex<Option<ConnectionManager>>,
    allow_memory_fallback: bool,
    mem_kv: Mutex<std::collections::HashMap<String, (String, Option<std::time::Instant>)>>,
    mem_sets: Mutex<std::collections::HashMap<String, std::collections::HashSet<String>>>,
}

impl RedisStore {
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
            client: Mutex::new(client),
            allow_memory_fallback: config.redis_allow_memory_fallback,
            mem_kv: Mutex::new(std::collections::HashMap::new()),
            mem_sets: Mutex::new(std::collections::HashMap::new()),
        })
    }

    pub fn is_ready(&self) -> bool {
        self.ready
    }

    pub async fn ping(&self) -> bool {
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
            redis::cmd("PING")
                .query_async::<String>(c)
                .await
                .map(|r| r == "PONG")
                .unwrap_or(false)
        } else {
            false
        }
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
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
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
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
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
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
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
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
            let script = redis::Script::new(
                "local v = redis.call('GET', KEYS[1]); if v then redis.call('DEL', KEYS[1]); end; return v",
            );
            let val: Option<String> = script.key(key).invoke_async(c).await?;
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
        self.set(&format!("fcm:{user_id}"), token, 30 * 24 * 60 * 60)
            .await
    }

    pub async fn get_fcm_token(&self, user_id: &str) -> Result<Option<String>> {
        self.get(&format!("fcm:{user_id}")).await
    }

    pub async fn sadd(&self, key: &str, member: &str) -> Result<()> {
        self.assert_fallback("sadd")?;
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
            let _: () = c.sadd(key, member).await?;
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
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
            let _: () = c.srem(key, member).await?;
        } else if let Some(set) = self.mem_sets.lock().await.get_mut(key) {
            set.remove(member);
        }
        Ok(())
    }

    pub async fn smembers(&self, key: &str) -> Result<Vec<String>> {
        self.assert_fallback("smembers")?;
        let mut guard = self.client.lock().await;
        if let Some(ref mut c) = *guard {
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
}
