use axum::{
    body::Body,
    extract::{Query, State},
    http::{HeaderMap, Request, StatusCode},
    middleware::Next,
    response::Response,
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::AppResult;
use crate::middleware::auth::{require_admin_page, verify_access, AuthUser};
use crate::state::AppState;

const LOG_COLS: &str =
    r#"id, level, type, method, path, "statusCode", "durationMs", "userId", ip, message, detail, "createdAt""#;

const SKIP_PREFIXES: &[&str] = &[
    "/system-logs",
    "/system-metrics",
    "/uploads",
    "/favicon",
    "/admin-user-list/summary",
];

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/admin", get(list_admin))
        .route("/admin/stats", get(stats))
        .route("/admin/purge", delete(purge_admin))
}

pub fn client_routes() -> Router<AppState> {
    Router::new().route("/", post(ingest_client_log))
}

#[derive(Deserialize)]
struct AdminListQuery {
    page: Option<String>,
    limit: Option<String>,
    r#type: Option<String>,
    level: Option<String>,
    problems: Option<String>,
    minDurationMs: Option<String>,
    method: Option<String>,
    status: Option<String>,
    search: Option<String>,
    from: Option<String>,
    to: Option<String>,
}

#[derive(Deserialize)]
struct PurgeQuery {
    olderThanDays: Option<String>,
}

enum SqlBind {
    Text(String),
    Int(i32),
}

#[derive(Deserialize)]
struct ClientLogBody {
    error: String,
    stackTrace: Option<String>,
    errorType: Option<String>,
    screen: Option<String>,
    appVersion: Option<String>,
    device: Option<String>,
}

struct RecordInput {
    level: String,
    log_type: String,
    method: Option<String>,
    path: Option<String>,
    status_code: Option<i32>,
    duration_ms: Option<i32>,
    user_id: Option<String>,
    ip: Option<String>,
    message: Option<String>,
    detail: Option<String>,
}

fn clip(s: Option<String>, max: usize) -> Option<String> {
    s.map(|v| {
        if v.len() > max {
            v[..max].to_string()
        } else {
            v
        }
    })
}

pub async fn record_log(state: &AppState, input: RecordInput) {
    let _ = sqlx::query(
        r#"INSERT INTO system_logs (id, level, type, method, path, "statusCode", "durationMs", "userId", ip, message, detail)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)"#,
    )
    .bind(Uuid::new_v4())
    .bind(&input.level)
    .bind(&input.log_type)
    .bind(input.method.as_deref())
    .bind(input.path.as_deref())
    .bind(input.status_code)
    .bind(input.duration_ms)
    .bind(input.user_id.as_deref())
    .bind(input.ip.as_deref())
    .bind(input.message.as_deref())
    .bind(input.detail.as_deref())
    .execute(&state.db)
    .await;
}

fn should_skip(method: &str, path: &str) -> bool {
    if SKIP_PREFIXES.iter().any(|p| path.starts_with(p)) {
        return true;
    }
    method == "GET" && (path == "/" || path == "/health" || path == "/healthz")
}

fn optional_user_id(state: &AppState, headers: &HeaderMap) -> Option<String> {
    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())?;
    let token = auth.strip_prefix("Bearer ")?;
    verify_access(state, token).ok().map(|c| c.sub)
}

fn client_ip(headers: &HeaderMap) -> Option<String> {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(|s| s.trim().to_string())
}

pub async fn api_logging_middleware(
    State(state): State<AppState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let method = request.method().to_string();
    let uri = request.uri().to_string();
    let path_only = uri.split('?').next().unwrap_or(&uri).to_string();

    if should_skip(&method, &path_only) {
        return next.run(request).await;
    }

    let started = std::time::Instant::now();
    let user_id = optional_user_id(&state, request.headers());
    let ip = client_ip(request.headers());
    let log_type = if path_only.starts_with("/auth") {
        "AUTH"
    } else {
        "API"
    };

    let response = next.run(request).await;
    let status = response.status().as_u16() as i32;
    // Persist failures only — successes are noise for the admin Logs page
    // and flood Postgres under live-worker load.
    if status < 400 {
        return response;
    }
    let duration_ms = started.elapsed().as_millis().min(i32::MAX as u128) as i32;
    let level = if status >= 500 { "ERROR" } else { "WARN" };

    let state = state.clone();
    let path = clip(Some(uri), 500);
    tokio::spawn(async move {
        record_log(
            &state,
            RecordInput {
                level: level.to_string(),
                log_type: log_type.to_string(),
                method: Some(method),
                path,
                status_code: Some(status),
                duration_ms: Some(duration_ms),
                user_id,
                ip,
                message: None,
                detail: None,
            },
        )
        .await;
    });

    response
}

async fn list_admin(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AdminListQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "logs")?;

    let page = q.page.as_deref().and_then(|p| p.parse().ok()).unwrap_or(1).max(1);
    let limit = q
        .limit
        .as_deref()
        .and_then(|l| l.parse().ok())
        .unwrap_or(50)
        .clamp(1, 200);
    let offset = (page - 1) * limit;

    let mut where_sql = String::from("WHERE 1=1");
    let mut binds: Vec<SqlBind> = Vec::new();

    if q.problems.as_deref() == Some("true") {
        where_sql.push_str(r#" AND level IN ('WARN', 'ERROR')"#);
    } else if let Some(level) = &q.level {
        if !level.is_empty() {
            binds.push(SqlBind::Text(level.clone()));
            where_sql.push_str(format!(" AND level = ${}", binds.len()).as_str());
        }
    }

    if let Some(t) = &q.r#type {
        if !t.is_empty() {
            binds.push(SqlBind::Text(t.clone()));
            where_sql.push_str(format!(" AND type = ${}", binds.len()).as_str());
        }
    }

    if let Some(m) = &q.method {
        if !m.is_empty() {
            binds.push(SqlBind::Text(m.to_uppercase()));
            where_sql.push_str(format!(" AND method = ${}", binds.len()).as_str());
        }
    }

    if let Some(ms) = &q.minDurationMs {
        if let Ok(n) = ms.parse::<i32>() {
            binds.push(SqlBind::Int(n.max(0)));
            where_sql.push_str(format!(" AND \"durationMs\" >= ${}", binds.len()).as_str());
        }
    }

    if let Some(status) = &q.status {
        let s = status.trim();
        if let Some(m) = s.strip_suffix("xx").and_then(|p| p.chars().next()) {
            if let Some(base) = m.to_digit(10) {
                let lo = (base * 100) as i32;
                binds.push(SqlBind::Int(lo));
                binds.push(SqlBind::Int(lo + 100));
                let i = binds.len();
                where_sql.push_str(
                    format!(
                        " AND \"statusCode\" >= ${} AND \"statusCode\" < ${}",
                        i - 1,
                        i
                    )
                    .as_str(),
                );
            }
        } else if s.len() == 3 && s.chars().all(|c| c.is_ascii_digit()) {
            if let Ok(code) = s.parse::<i32>() {
                binds.push(SqlBind::Int(code));
                where_sql.push_str(format!(" AND \"statusCode\" = ${}", binds.len()).as_str());
            }
        }
    }

    if let Some(search) = &q.search {
        let term = search.trim();
        if !term.is_empty() {
            binds.push(SqlBind::Text(format!("%{}%", term)));
            let idx = binds.len();
            where_sql.push_str(
                format!(" AND (path ILIKE ${} OR message ILIKE ${})", idx, idx).as_str(),
            );
        }
    }

    if let Some(from) = &q.from {
        if !from.is_empty() {
            binds.push(SqlBind::Text(from.clone()));
            where_sql.push_str(format!(" AND \"createdAt\" >= ${}::timestamptz", binds.len()).as_str());
        }
    }

    if let Some(to) = &q.to {
        if !to.is_empty() {
            binds.push(SqlBind::Text(to.clone()));
            where_sql.push_str(format!(" AND \"createdAt\" <= ${}::timestamptz", binds.len()).as_str());
        }
    }

    let count_sql = format!("SELECT COUNT(*)::bigint FROM system_logs {}", where_sql);
    let mut count_q = sqlx::query_scalar::<_, i64>(&count_sql);
    for b in &binds {
        count_q = match b {
            SqlBind::Text(v) => count_q.bind(v),
            SqlBind::Int(v) => count_q.bind(v),
        };
    }
    let total = count_q.fetch_one(&state.db).await?;

    let list_sql = format!(
        "SELECT {LOG_COLS} FROM system_logs {} ORDER BY \"createdAt\" DESC LIMIT {} OFFSET {}",
        where_sql,
        limit,
        offset
    );
    let mut list_q = sqlx::query(&list_sql);
    for b in &binds {
        list_q = match b {
            SqlBind::Text(v) => list_q.bind(v),
            SqlBind::Int(v) => list_q.bind(v),
        };
    }
    let rows = list_q.fetch_all(&state.db).await?;
    let pages = if total == 0 {
        0
    } else {
        (total + limit - 1) / limit
    };

    Ok(Json(json!({
        "data": rows.iter().map(log_json).collect::<Vec<_>>(),
        "total": total,
        "page": page,
        "limit": limit,
        "pages": pages,
    })))
}

async fn stats(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    require_admin_page(&user, "logs")?;
    let since = chrono::Utc::now() - chrono::Duration::hours(24);
    let rows = sqlx::query(
        r#"SELECT type, level, COUNT(*)::bigint AS count
           FROM system_logs
           WHERE "createdAt" >= $1
           GROUP BY type, level"#,
    )
    .bind(since)
    .fetch_all(&state.db)
    .await?;

    let mut by_type = serde_json::Map::new();
    let mut by_level = serde_json::Map::new();
    let mut total = 0i64;
    for r in &rows {
        let n = r.get::<i64, _>("count");
        let t = r.get::<String, _>("type");
        let l = r.get::<String, _>("level");
        by_type.insert(t.clone(), json!(by_type.get(&t).and_then(|v| v.as_i64()).unwrap_or(0) + n));
        by_level.insert(l.clone(), json!(by_level.get(&l).and_then(|v| v.as_i64()).unwrap_or(0) + n));
        total += n;
    }

    Ok(Json(json!({
        "since": since,
        "total": total,
        "byType": by_type,
        "byLevel": by_level,
    })))
}

async fn purge_admin(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<PurgeQuery>,
) -> AppResult<Json<Value>> {
    require_admin_page(&user, "logs")?;
    let days = q
        .olderThanDays
        .as_deref()
        .and_then(|d| d.parse().ok())
        .unwrap_or(30)
        .clamp(1, 365);
    let result = sqlx::query(
        r#"DELETE FROM system_logs WHERE "createdAt" < NOW() - make_interval(days => $1)"#,
    )
    .bind(days)
    .execute(&state.db)
    .await?;
    Ok(Json(json!({
        "deleted": result.rows_affected(),
        "olderThanDays": days,
    })))
}

async fn ingest_client_log(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<ClientLogBody>,
) -> AppResult<StatusCode> {
    let user_id = optional_user_id(&state, &headers);
    let ip = client_ip(&headers);

    let mut message = body.error.clone();
    if let Some(t) = &body.errorType {
        message = format!("[{}] {}", t, message);
    }
    if let Some(screen) = &body.screen {
        message = format!("{} @ {}", message, screen);
    }

    let mut detail_parts = Vec::new();
    if let Some(stack) = &body.stackTrace {
        detail_parts.push(stack.clone());
    }
    if let Some(v) = &body.appVersion {
        detail_parts.push(format!("App version: {}", v));
    }
    if let Some(d) = &body.device {
        detail_parts.push(format!("Device: {}", d));
    }

    record_log(
        &state,
        RecordInput {
            level: "ERROR".to_string(),
            log_type: "APP_CRASH".to_string(),
            method: Some("APP".to_string()),
            path: clip(body.screen.clone(), 500),
            status_code: None,
            duration_ms: None,
            user_id,
            ip,
            message: clip(Some(message), 500),
            detail: clip(
                if detail_parts.is_empty() {
                    None
                } else {
                    Some(detail_parts.join("\n"))
                },
                8000,
            ),
        },
    )
    .await;

    Ok(StatusCode::NO_CONTENT)
}

fn log_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "level": row.get::<String, _>("level"),
        "type": row.get::<String, _>("type"),
        "method": row.get::<Option<String>, _>("method"),
        "path": row.get::<Option<String>, _>("path"),
        "statusCode": row.get::<Option<i32>, _>("statusCode"),
        "durationMs": row.get::<Option<i32>, _>("durationMs"),
        "userId": row.get::<Option<String>, _>("userId"),
        "ip": row.get::<Option<String>, _>("ip"),
        "message": row.get::<Option<String>, _>("message"),
        "detail": row.get::<Option<String>, _>("detail"),
        "createdAt": row.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
    })
}
