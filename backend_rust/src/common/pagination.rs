use axum::extract::Query;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct PaginationQuery {
    pub page: Option<String>,
    pub limit: Option<String>,
}

pub fn parse_pagination(page: Option<&str>, limit: Option<&str>) -> (i64, i64) {
    let page = page.and_then(|p| p.parse().ok()).unwrap_or(1).max(1);
    let limit = limit.and_then(|l| l.parse().ok()).unwrap_or(20).clamp(1, 100);
    (page, limit)
}

pub fn pagination_offset(page: i64, limit: i64) -> i64 {
    (page - 1) * limit
}
