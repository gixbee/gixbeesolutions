mod addresses;
mod admin_staff;
mod auth;
mod billing;
mod bookings;
mod businesses;
mod cities;
mod common;
mod config;
mod error;
mod events;
mod favourites;
mod hiring;
mod hiring_catalogue;
mod jobs;
mod master_entries;
mod matching;
mod match_engine;
mod messages;
mod middleware;
mod notifications;
mod outbox;
mod payments;
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
use std::sync::Arc;

use axum::{middleware::from_fn_with_state, routing::get, Router};
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

    let db = connect_db(&config.database_url).await?;
    let redis = Arc::new(RedisStore::connect(&config).await?);

    if !redis.is_ready() && !config.redis_allow_memory_fallback {
        anyhow::bail!(
            "Redis is required for Socket.IO across backend replicas. Start Redis or set REDIS_ALLOW_MEMORY_FALLBACK=true for single-process local dev."
        );
    }

    let http = reqwest::Client::new();
    let fcm = Arc::new(FcmService::from_config(&config, http.clone()));

    let state = AppState {
        config: config.clone(),
        db,
        redis,
        http,
        realtime: Arc::new(RealtimeHub),
        fcm,
    };

    let (socket_layer, io) = realtime::build_socket_layer(&config.redis_url, state.clone()).await?;
    realtime::register_handlers(&io).await?;

    let poller_state = state.clone();
    tokio::spawn(async move {
        outbox::run_poller(poller_state).await;
    });
    tokio::spawn(matching::run_scheduler(state.clone()));
    tokio::spawn(jobs::run_scheduler(state.clone()));
    let embed_state = state.clone();
    tokio::spawn(async move {
        crate::match_engine::persist::backfill_embeddings(&embed_state).await;
    });

    let logging_state = state.clone();
    let uploads = ServeDir::new(&config.uploads_dir);
    let app = Router::new()
        .route("/", get(|| async { "Hello World!" }))
        .nest_service("/uploads", uploads)
        .merge(api_router())
        .layer(socket_layer)
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
        .with_state(state);

    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    tracing::info!("Gixbee Rust backend running on http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
