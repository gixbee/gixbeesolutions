use axum::Router;

use crate::activity;
use crate::addresses;
use crate::admin_staff;
use crate::auth;
use crate::billing;
use crate::bookings;
use crate::businesses;
use crate::cities;
use crate::favourites;
use crate::hiring;
use crate::master_admin;
use crate::master_entries;
use crate::matching;
use crate::messages;
use crate::notifications;
use crate::payments;
use crate::redis_admin;
use crate::rentals;
use crate::support;
use crate::system_logs;
use crate::system_metrics;
use crate::talent;
use crate::uploads;
use crate::users;
use crate::wallets;
use crate::workers;
use crate::state::AppState;

pub fn api_router() -> Router<AppState> {
    Router::new()
        .nest("/activity", activity::routes())
        .nest("/auth", auth::routes())
        .nest("/addresses", addresses::routes())
        .nest("/admin-staff", admin_staff::routes())
        .nest("/billing/credits", billing::routes())
        .nest("/bookings", bookings::routes())
        .nest("/businesses", businesses::routes())
        .nest("/businesses", crate::halls::routes())
        .nest("/businesses", crate::hall_enquiries::routes())
        .nest("/halls", crate::halls::public_routes())
        .nest("/cache", crate::cache::http::routes())
        .nest("/cities", cities::routes())
        .nest("/client-logs", system_logs::client_routes())
        .nest("/favourites", favourites::routes())
        .nest("/events", crate::events::routes())
        .nest("/hiring", hiring::routes())
        .nest("/hiring/catalogue", crate::hiring_catalogue::routes())
        .nest("/hiring/locations", crate::hiring_catalogue::location_routes())
        .nest("/hiring/match", matching::routes())
        .nest("/master-admin", master_admin::routes())
        .nest("/master-entries", master_entries::routes())
        .nest("/messages", messages::routes())
        .nest("/notifications", notifications::routes())
        .nest("/payments", payments::routes())
        .nest("/plans", crate::plans::routes())
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
}
