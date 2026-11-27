mod activity;
mod addresses;
mod admin_staff;
mod auth;
mod billing;
mod bookings;
mod businesses;
mod cache;
mod cities;
mod common;
mod config;
mod error;
mod events;
mod favourites;
mod hall_enquiries;
mod halls;
mod hiring;
mod hiring_catalogue;
mod jobs;
mod master_admin;
mod master_audit;
mod master_entries;
mod matching;
mod match_engine;
mod messages;
mod middleware;
mod notifications;
mod outbox;
mod payments;
mod plans;
mod redis;
mod redis_admin;
mod rentals;
mod realtime;
mod routes;
mod state;
mod support;
mod system_logs;
mod system_metrics;
mod talent;
mod uploads;
mod users;
mod wallets;
mod workers;
#[cfg(test)]
mod marketplace_tests;

use std::net::SocketAddr;
use std::sync::{Arc, OnceLock};

use axum::{extract::{Request, State}, http::StatusCode, middleware::from_fn_with_state, routing::get, Json, Router};
use tower::ServiceExt;
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;
use tower_http::trace::TraceLayer;

use crate::config::{assert_production_secrets, connect_db, Config};
use crate::notifications::FcmService;
use crate::realtime::RealtimeHub;
use crate::redis::RedisStore;
use crate::routes::api_router;
use crate::state::AppState;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "gixbee_backend=info,tower_http=info".into()),
        )
        .init();

    let config = Config::from_env()?;
    assert_production_secrets(&config)?;
    if std::env::args().any(|arg| arg == "--check-config") {
        anyhow::ensure!(config.is_production, "Expected production configuration");
        return Ok(());
    }

    let db = connect_db(&config.database_url).await?;
    if !config.is_production {
        if let Err(e) = cache::versions::ensure_table(&db).await {
            tracing::warn!("cache_versions table ensure failed (run migration): {e}");
        }
    }
    let cache_url = std::env::var("CACHE_REDIS_URL").ok();
    let (redis, cache_redis) = tokio::try_join!(
        RedisStore::connect(Some(&config.redis_url), config.redis_allow_memory_fallback),
        RedisStore::connect(cache_url.as_deref().filter(|url| !url.is_empty()), false),
    )?;

    let http = reqwest::Client::new();
    let fcm = Arc::new(FcmService::from_config(&config, http.clone()));

    let state = AppState {
        config: config.clone(),
        cache: cache::CacheConfig::from_env(),
        db,
        redis,
        cache_redis,
        http,
        realtime: Arc::new(RealtimeHub),
        fcm,
    };

    let poller_state = state.clone();
    tokio::spawn(async move {
        outbox::run_poller(poller_state).await;
    });
    tokio::spawn(matching::run_scheduler(state.clone()));
    tokio::spawn(jobs::run_scheduler(state.clone()));
    tokio::spawn(payments::run_reconciliation(state.clone()));
    let embed_state = state.clone();
    tokio::spawn(async move {
        crate::match_engine::persist::backfill_embeddings(&embed_state).await;
    });

    let logging_state = state.clone();
    let uploads = ServeDir::new(&config.uploads_dir);
    let http_app: Router = Router::new()
        .route("/", get(|| async { "Hello World!" }))
        .route("/readyz", get(readiness))
        .nest_service("/uploads", uploads)
        .merge(api_router())
        .layer(from_fn_with_state(
            logging_state,
            system_logs::api_logging_middleware,
        ))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .layer(TraceLayer::new_for_http())
        .with_state(state.clone());

    let socket_app = Arc::new(OnceLock::<Router>::new());
    let socket_slot = socket_app.clone();
    let socket_base = http_app.clone();
    tokio::spawn(async move {
        loop {
            let setup = async {
                let (layer, io) = realtime::build_socket_layer(&state.config.redis_url, state.clone()).await?;
                realtime::register_handlers(&io).await?;
                Ok::<_, anyhow::Error>(layer)
            };
            if let Ok(Ok(layer)) = tokio::time::timeout(std::time::Duration::from_secs(3), setup).await {
                let _ = socket_slot.set(socket_base.layer(layer));
                break;
            }
            tracing::warn!("Socket.IO unavailable; HTTP continues while Socket.IO retries");
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        }
    });
    let app = Router::new().fallback(move |request: Request| {
        let app = socket_app.get().unwrap_or(&http_app).clone();
        async move { app.oneshot(request).await.expect("Router is infallible") }
    });

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("Gixbee Rust backend running on http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn readiness(State(state): State<AppState>) -> (StatusCode, Json<serde_json::Value>) {
    let timeout = std::time::Duration::from_millis(500);
    let (postgres, redis) = tokio::join!(
        tokio::time::timeout(timeout, sqlx::query("SELECT 1").execute(&state.db)),
        tokio::time::timeout(timeout, state.redis.ping()),
    );
    let postgres = matches!(postgres, Ok(Ok(_)));
    let redis = matches!(redis, Ok(true));
    let status = if postgres { StatusCode::OK } else { StatusCode::SERVICE_UNAVAILABLE };
    (status, Json(serde_json::json!({"postgres": postgres, "redis": redis})))
}
