pub mod addresses;
pub mod admin_staff;
pub mod auth;
pub mod billing;
pub mod bookings;
pub mod businesses;
pub mod cities;
pub mod favourites;
pub mod hiring;
pub mod master_entries;
pub mod matching;
pub mod messages;
pub mod notifications;
pub mod payments;
pub mod redis_admin;
pub mod rentals;
pub mod support;
pub mod system_logs;
pub mod system_metrics;
pub mod talent;
pub mod uploads;
pub mod users;
pub mod voice_calls;
pub mod wallets;
pub mod worker_engine;
pub mod workers;

use axum::Router;

use crate::state::AppState;

pub fn api_router() -> Router<AppState> {
    Router::new()
        .nest("/auth", auth::routes())
        .nest("/addresses", addresses::routes())
        .nest("/admin-staff", admin_staff::routes())
        .nest("/billing/credits", billing::routes())
        .nest("/bookings", bookings::routes())
        .nest("/businesses", businesses::routes())
        .nest("/cities", cities::routes())
        .nest("/client-logs", system_logs::client_routes())
        .nest("/favourites", favourites::routes())
        .nest("/hiring", hiring::routes())
        .nest("/hiring/match", matching::routes())
        .nest("/master-entries", master_entries::routes())
        .nest("/messages", messages::routes())
        .nest("/notifications", notifications::routes())
        .nest("/payments", payments::routes())
        .nest("/redis/admin", redis_admin::routes())
        .nest("/rentals", rentals::routes())
        .nest("/support", support::routes())
        .nest("/system-logs", system_logs::routes())
        .nest("/system-metrics", system_metrics::routes())
        .nest("/talent", talent::routes())
        .nest("/admin-user-list", users::routes())
        .nest("/wallets", wallets::routes())
        .nest("/workers", workers::routes())
        .merge(uploads::routes())
        .merge(voice_calls::routes())
}
