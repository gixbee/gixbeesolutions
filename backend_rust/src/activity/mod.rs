use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new().route("/feed", get(feed))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FeedQuery {
    category: Option<String>,
    phase: Option<String>,
    status_group: Option<String>,
    page: Option<i64>,
    limit: Option<i64>,
}

#[derive(Clone, Copy)]
enum Phase {
    Active,
    History,
}

impl Phase {
    fn parse(raw: Option<&str>) -> Self {
        match raw.map(|s| s.to_ascii_lowercase()).as_deref() {
            Some("history") | Some("closed") | Some("past") => Phase::History,
            _ => Phase::Active,
        }
    }
}

fn category_allowed(filter: &Option<String>, want: &str) -> bool {
    match filter.as_deref() {
        None | Some("") | Some("all") | Some("ALL") => true,
        Some(c) => c.eq_ignore_ascii_case(want),
    }
}

async fn feed(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<FeedQuery>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let page = q.page.unwrap_or(1).max(1);
    let limit = q.limit.unwrap_or(20).clamp(1, 50);
    let offset = (page - 1) * limit;
    let phase = Phase::parse(q.phase.as_deref());
    let cat = q.category.clone();
    let status_group = q
        .status_group
        .as_deref()
        .map(|s| s.to_ascii_lowercase())
        .filter(|s| !s.is_empty());

    let mut union_parts: Vec<String> = Vec::new();

    if category_allowed(&cat, "services") {
        union_parts.push(services_union_sql(phase));
    }
    if category_allowed(&cat, "rentals") {
        union_parts.push(rentals_union_sql(phase));
    }
    if category_allowed(&cat, "events") {
        union_parts.push(events_plans_union_sql(phase));
        union_parts.push(events_vendor_quotes_union_sql(phase));
        union_parts.push(hall_enquiries_union_sql(phase));
    }
    if category_allowed(&cat, "job_applications") {
        union_parts.push(job_applications_union_sql(phase));
    }
    if category_allowed(&cat, "hiring") {
        union_parts.push(hiring_requests_union_sql(phase));
    }

    if union_parts.is_empty() {
        return Ok(Json(json!({
            "items": [],
            "page": page,
            "limit": limit,
            "hasMore": false,
            "categoriesAvailable": categories_available(&state, uid).await?,
        })));
    }

    let union_sql = union_parts.join("\nUNION ALL\n");
    let sql = format!(
        r#"WITH feed AS ({union_sql})
           SELECT * FROM feed
           WHERE ($1::text IS NULL OR status_group = $1)
           ORDER BY sort_rank ASC,
             CASE WHEN phase = 'active' AND sort_at > NOW() THEN sort_at END ASC NULLS LAST,
             sort_at DESC NULLS LAST,
             category ASC, id ASC
           LIMIT $2 OFFSET $3"#
    );

    let rows = sqlx::query(&sql)
        .bind(status_group.as_deref())
        .bind(limit + 1)
        .bind(offset)
        .bind(uid)
        .fetch_all(&state.db)
        .await
        .map_err(|e| AppError::Internal(format!("activity feed: {e}")))?;

    let has_more = rows.len() as i64 > limit;
    let items: Vec<Value> = rows
        .into_iter()
        .take(limit as usize)
        .map(row_to_item)
        .collect();

    Ok(Json(json!({
        "items": items,
        "page": page,
        "limit": limit,
        "hasMore": has_more,
        "categoriesAvailable": categories_available(&state, uid).await?,
    })))
}

async fn categories_available(state: &AppState, uid: Uuid) -> AppResult<Vec<&'static str>> {
    let mut out: Vec<&'static str> = Vec::new();
    let svc: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM bookings WHERE "customerId"=$1 OR "operatorId"=$1)"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if svc {
        out.push("services");
    }
    let rent: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM rental_reservations r JOIN rental_items i ON i.id=r."itemId"
            WHERE r."renterId"=$1 OR i."ownerId"=$1)"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if rent {
        out.push("rentals");
    }
    let ev: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM event_plans WHERE "customerId"=$1)
           OR EXISTS(SELECT 1 FROM event_quotes q JOIN businesses b ON b.id=q."businessId" WHERE b."ownerId"=$1)
           OR EXISTS(SELECT 1 FROM hall_enquiries e JOIN businesses b ON b.id=e."businessId" WHERE b."ownerId"=$1)"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if ev {
        out.push("events");
    }
    let apps: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM job_applications WHERE "applicantId"=$1)"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if apps {
        out.push("job_applications");
    }
    let hire: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM hiring_requests WHERE "employerId"=$1)"#,
    )
    .bind(uid)
    .fetch_one(&state.db)
    .await?;
    if hire {
        out.push("hiring");
    }
    Ok(out)
}

fn row_to_item(row: sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<String, _>("id"),
        "category": row.get::<String, _>("category"),
        "dedupeKey": row.get::<String, _>("dedupe_key"),
        "phase": row.get::<String, _>("phase"),
        "status": row.get::<String, _>("status"),
        "statusGroup": row.get::<String, _>("status_group"),
        "title": row.get::<String, _>("title"),
        "subtitle": row.get::<Option<String>, _>("subtitle"),
        "counterparty": row.get::<Option<String>, _>("counterparty"),
        "roleLabel": row.get::<String, _>("role_label"),
        "sortAt": row.try_get::<Option<DateTime<Utc>>, _>("sort_at").ok().flatten(),
        "parentEventId": row.try_get::<Option<String>, _>("parent_event_id").ok().flatten(),
        "detail": {
            "kind": row.get::<String, _>("detail_kind"),
            "id": row.get::<String, _>("id"),
            "extra": row.try_get::<Option<Value>, _>("detail_extra").ok().flatten(),
        },
        "primaryAction": row.get::<String, _>("primary_action"),
    })
}

fn services_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => r#"b.status::text IN (
            'REQUESTED','CUSTOM_REQUESTED','PENDING','ACCEPTED','CONFIRMED',
            'ACTIVE','ARRIVED','IN_PROGRESS','CANCEL_REQUESTED')"#,
        Phase::History => {
            r#"b.status::text IN ('COMPLETED','CANCELLED','REJECTED')"#
        }
    };
    format!(
        r#"SELECT
            'services'::text AS category,
            b.id::text AS id,
            ('services:booking:' || b.id::text) AS dedupe_key,
            CASE WHEN b.status::text IN ('COMPLETED','CANCELLED','REJECTED') THEN 'history' ELSE 'active' END AS phase,
            b.status::text AS status,
            CASE
              WHEN b.status::text IN ('REQUESTED','CUSTOM_REQUESTED','PENDING') THEN 'upcoming'
              WHEN b.status::text IN ('ACCEPTED','CONFIRMED','ACTIVE','ARRIVED','IN_PROGRESS') THEN 'in_progress'
              WHEN b.status::text = 'CANCEL_REQUESTED' THEN 'action_needed'
              WHEN b.status::text IN ('COMPLETED') THEN 'completed'
              ELSE 'closed'
            END AS status_group,
            COALESCE(NULLIF(b.skill,''), 'Service booking') AS title,
            COALESCE(b."serviceLocation", '') AS subtitle,
            CASE WHEN b."customerId" = $4 THEN COALESCE(op.name, 'Pro')
                 ELSE COALESCE(cu.name, 'Customer') END AS counterparty,
            CASE WHEN b."customerId" = $4 THEN 'Booked service'
                 ELSE 'Work received' END AS role_label,
            CASE
              WHEN b.status::text = 'CANCEL_REQUESTED' THEN 0
              WHEN b.status::text IN ('REQUESTED','CUSTOM_REQUESTED','PENDING') AND b."operatorId" = $4 THEN 1
              WHEN b.status::text IN ('ACTIVE','ARRIVED','IN_PROGRESS') THEN 2
              WHEN b.status::text IN ('ACCEPTED','CONFIRMED') THEN 3
              ELSE 10
            END AS sort_rank,
            COALESCE(b."scheduledAt", b."createdAt") AS sort_at,
            NULL::text AS parent_event_id,
            'booking'::text AS detail_kind,
            NULL::jsonb AS detail_extra,
            'open_booking'::text AS primary_action
        FROM bookings b
        LEFT JOIN users cu ON cu.id = b."customerId"
        LEFT JOIN users op ON op.id = b."operatorId"
        WHERE (b."customerId" = $4 OR b."operatorId" = $4)
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn rentals_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => r#"r.status::text IN (
            'TEMP_HOLD','PAYMENT_PENDING','PENDING','PENDING_OWNER_CONFIRMATION',
            'CONFIRMED','ACTIVE','RETURN_PENDING')"#,
        Phase::History => r#"r.status::text IN ('COMPLETED','CANCELLED','REJECTED')"#,
    };
    format!(
        r#"SELECT
            'rentals'::text AS category,
            r.id::text AS id,
            ('rentals:reservation:' || r.id::text) AS dedupe_key,
            CASE WHEN r.status::text IN ('COMPLETED','CANCELLED','REJECTED') THEN 'history' ELSE 'active' END AS phase,
            r.status::text AS status,
            CASE
              WHEN r.status::text IN ('PENDING_OWNER_CONFIRMATION','PAYMENT_PENDING') THEN 'action_needed'
              WHEN r.status::text IN ('CONFIRMED','ACTIVE','RETURN_PENDING') THEN 'in_progress'
              WHEN r.status::text IN ('TEMP_HOLD','PENDING') THEN 'upcoming'
              WHEN r.status::text = 'COMPLETED' THEN 'completed'
              ELSE 'closed'
            END AS status_group,
            COALESCE(i.name, 'Rental item') AS title,
            (to_char(r."startTime", 'YYYY-MM-DD') || ' → ' || to_char(r."endTime", 'YYYY-MM-DD')) AS subtitle,
            CASE WHEN r."renterId" = $4 THEN COALESCE(own.name, 'Owner')
                 ELSE COALESCE(u.name, 'Renter') END AS counterparty,
            CASE WHEN r."renterId" = $4 THEN 'Rented item'
                 ELSE 'Rental supplied' END AS role_label,
            CASE
              WHEN r.status::text = 'RETURN_PENDING' THEN 0
              WHEN r.status::text = 'PENDING_OWNER_CONFIRMATION' AND i."ownerId" = $4 THEN 1
              WHEN r.status::text IN ('ACTIVE','CONFIRMED') THEN 2
              ELSE 8
            END AS sort_rank,
            COALESCE(r."endTime", r."startTime", r."createdAt") AS sort_at,
            NULL::text AS parent_event_id,
            'rental_reservation'::text AS detail_kind,
            jsonb_build_object(
              'itemId', i.id::text,
              'asOwner', i."ownerId" = $4,
              'businessId', i."businessId"::text
            ) AS detail_extra,
            'open_rental'::text AS primary_action
        FROM rental_reservations r
        JOIN rental_items i ON i.id = r."itemId"
        LEFT JOIN users u ON u.id = r."renterId"
        LEFT JOIN users own ON own.id = i."ownerId"
        WHERE (r."renterId" = $4 OR i."ownerId" = $4)
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn events_plans_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => {
            r#"p."cancelledAt" IS NULL AND COALESCE(p."endTime", p."startTime") > NOW()"#
        }
        Phase::History => {
            r#"p."cancelledAt" IS NOT NULL OR COALESCE(p."endTime", p."startTime") <= NOW()"#
        }
    };
    format!(
        r#"SELECT
            'events'::text AS category,
            p.id::text AS id,
            ('events:plan:' || p.id::text) AS dedupe_key,
            CASE WHEN p."cancelledAt" IS NOT NULL
                   OR COALESCE(p."endTime", p."startTime") <= NOW()
                 THEN 'history' ELSE 'active' END AS phase,
            CASE WHEN p."cancelledAt" IS NOT NULL THEN 'CANCELLED' ELSE 'PLANNED' END AS status,
            CASE
              WHEN p."cancelledAt" IS NOT NULL THEN 'closed'
              WHEN p."startTime" > NOW() THEN 'upcoming'
              WHEN COALESCE(p."endTime", p."startTime") <= NOW() THEN
                CASE WHEN EXISTS (
                  SELECT 1 FROM event_quotes q
                  WHERE q."planId" = p.id
                    AND q.status::text IN ('OFFERED','CONFIRMED','CANCEL_REQUESTED')
                ) THEN 'action_needed'
                ELSE 'completed'
                END
              ELSE 'in_progress'
            END AS status_group,
            COALESCE(p."eventType", 'Event') AS title,
            COALESCE(p.location, '') AS subtitle,
            NULL::text AS counterparty,
            'Event plan'::text AS role_label,
            CASE WHEN p."cancelledAt" IS NULL AND p."startTime" > NOW() THEN 4 ELSE 11 END AS sort_rank,
            p."startTime" AS sort_at,
            NULL::text AS parent_event_id,
            'event_plan'::text AS detail_kind,
            NULL::jsonb AS detail_extra,
            'open_event_plan'::text AS primary_action
        FROM event_plans p
        WHERE p."customerId" = $4
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn hall_enquiries_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => {
            r#"e.status IN ('PENDING_OWNER','OWNER_APPROVED','ASSIGNED','QUOTE_OFFERED','CUSTOMER_ACCEPTED')"#
        }
        Phase::History => {
            r#"e.status IN ('OWNER_DECLINED','QUOTE_DECLINED','QUOTE_EXPIRED','CANCELLED')"#
        }
    };
    format!(
        r#"SELECT
            'events'::text AS category,
            e.id::text AS id,
            ('events:hall_enquiry:' || e.id::text) AS dedupe_key,
            CASE WHEN e.status IN ('OWNER_DECLINED','QUOTE_DECLINED','QUOTE_EXPIRED','CANCELLED')
                 THEN 'history' ELSE 'active' END AS phase,
            e.status AS status,
            CASE
              WHEN e.status IN ('PENDING_OWNER','ASSIGNED','QUOTE_OFFERED') THEN 'action_needed'
              WHEN e.status IN ('OWNER_APPROVED','CUSTOMER_ACCEPTED') THEN 'in_progress'
              ELSE 'closed'
            END AS status_group,
            (COALESCE(p."eventType", 'Event') || ' · Hall enquiry') AS title,
            COALESCE(p.location, '') AS subtitle,
            COALESCE(b.name, '') AS counterparty,
            'Hall enquiry'::text AS role_label,
            CASE WHEN e.status = 'PENDING_OWNER' THEN 2 ELSE 8 END AS sort_rank,
            COALESCE(p."startTime", e."createdAt") AS sort_at,
            p.id::text AS parent_event_id,
            'hall_enquiry'::text AS detail_kind,
            jsonb_build_object(
              'planId', p.id::text,
              'businessId', b.id::text,
              'enquiryId', e.id::text,
              'hallId', e."assignedHallId"::text
            ) AS detail_extra,
            'open_hall_enquiries'::text AS primary_action
        FROM hall_enquiries e
        JOIN event_plans p ON p.id = e."eventPlanId"
        JOIN businesses b ON b.id = e."businessId"
        WHERE b."ownerId" = $4
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn events_vendor_quotes_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => r#"q.status::text IN ('OFFERED','CONFIRMED','CANCEL_REQUESTED')"#,
        Phase::History => {
            r#"q.status::text IN ('COMPLETED','CANCELLED','REJECTED','DECLINED','EXPIRED')"#
        }
    };
    format!(
        r#"SELECT
            'events'::text AS category,
            q.id::text AS id,
            ('events:quote:' || q.id::text) AS dedupe_key,
            CASE WHEN q.status::text IN ('COMPLETED','CANCELLED','REJECTED','DECLINED','EXPIRED')
                 THEN 'history' ELSE 'active' END AS phase,
            q.status::text AS status,
            CASE
              WHEN q.status::text = 'OFFERED' THEN 'action_needed'
              WHEN q.status::text IN ('CONFIRMED','CANCEL_REQUESTED') THEN 'in_progress'
              WHEN q.status::text = 'COMPLETED' THEN 'completed'
              ELSE 'closed'
            END AS status_group,
            (COALESCE(p."eventType", 'Event') || ' · ' || COALESCE(b.name, 'Vendor quote')) AS title,
            COALESCE(p.location, '') AS subtitle,
            NULL::text AS counterparty,
            'Vendor quote'::text AS role_label,
            CASE WHEN q.status::text = 'OFFERED' THEN 3 ELSE 9 END AS sort_rank,
            COALESCE(p."startTime", q."createdAt") AS sort_at,
            p.id::text AS parent_event_id,
            'event_quote'::text AS detail_kind,
            jsonb_build_object('planId', p.id::text, 'businessId', b.id::text) AS detail_extra,
            'open_event_plan'::text AS primary_action
        FROM event_quotes q
        JOIN event_plans p ON p.id = q."planId"
        JOIN businesses b ON b.id = q."businessId"
        WHERE b."ownerId" = $4
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn job_applications_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => r#"a.status::text IN ('APPLIED','INTERVIEW','SELECTED')"#,
        Phase::History => r#"a.status::text IN ('REJECTED','WITHDRAWN','NO_SHOW')"#,
    };
    format!(
        r#"SELECT
            'job_applications'::text AS category,
            a.id::text AS id,
            ('job_applications:' || a.id::text) AS dedupe_key,
            CASE WHEN a.status::text IN ('REJECTED','WITHDRAWN','NO_SHOW') THEN 'history' ELSE 'active' END AS phase,
            a.status::text AS status,
            CASE
              WHEN a.status::text = 'APPLIED' THEN 'applied'
              WHEN a.status::text = 'INTERVIEW' THEN 'interview'
              WHEN a.status::text = 'SELECTED' THEN 'hired'
              WHEN a.status::text = 'REJECTED' THEN 'closed'
              WHEN a.status::text = 'NO_SHOW' THEN 'closed'
              ELSE 'withdrawn'
            END AS status_group,
            COALESCE(j.title, 'Job application') AS title,
            COALESCE(j.location, '') AS subtitle,
            COALESCE(emp.name, '') AS counterparty,
            'Job application'::text AS role_label,
            CASE WHEN a.status::text = 'APPLIED' THEN 5 ELSE 7 END AS sort_rank,
            COALESCE(a."updatedAt", a."createdAt") AS sort_at,
            NULL::text AS parent_event_id,
            'job_application'::text AS detail_kind,
            jsonb_build_object('jobPostId', j.id::text) AS detail_extra,
            'open_job_application'::text AS primary_action
        FROM job_applications a
        JOIN job_posts j ON j.id = a."jobPostId"
        LEFT JOIN users emp ON emp.id = j."employerId"
        WHERE a."applicantId" = $4
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}

fn hiring_requests_union_sql(phase: Phase) -> String {
    let phase_filter = match phase {
        Phase::Active => r#"hr.status::text IN ('COLLECTING','DELIVERED')"#,
        Phase::History => r#"hr.status::text NOT IN ('COLLECTING','DELIVERED')"#,
    };
    format!(
        r#"SELECT
            'hiring'::text AS category,
            hr.id::text AS id,
            ('hiring:request:' || hr.id::text) AS dedupe_key,
            CASE WHEN hr.status::text NOT IN ('COLLECTING','DELIVERED') THEN 'history' ELSE 'active' END AS phase,
            hr.status::text AS status,
            CASE
              WHEN hr.status::text = 'COLLECTING' THEN 'collecting'
              WHEN hr.status::text = 'DELIVERED' THEN 'delivered'
              ELSE 'closed'
            END AS status_group,
            COALESCE(hr."jobType", 'Hiring request') AS title,
            COALESCE(hr.location, '') AS subtitle,
            NULL::text AS counterparty,
            'Hiring request'::text AS role_label,
            CASE WHEN hr.status::text = 'COLLECTING' THEN 4 ELSE 10 END AS sort_rank,
            COALESCE(hr."deadlineAt", hr."createdAt") AS sort_at,
            NULL::text AS parent_event_id,
            'hiring_request'::text AS detail_kind,
            jsonb_build_object(
              'vacancies', hr.vacancies,
              'interestedCount', (
                SELECT count(*)::int FROM hiring_interests hi
                WHERE hi."requestId" = hr.id AND hi.response::text = 'INTERESTED'
              )
            ) AS detail_extra,
            'open_hiring_request'::text AS primary_action
        FROM hiring_requests hr
        WHERE hr."employerId" = $4
          AND ({phase_filter})"#,
        phase_filter = phase_filter,
    )
}
