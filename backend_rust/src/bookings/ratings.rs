use rust_decimal::prelude::ToPrimitive;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{Postgres, Row, Transaction};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;
use crate::workers;

fn validate_rating(rating: i32) -> AppResult<()> {
    if rating < 1 || rating > 5 {
        return Err(AppError::BadRequest("Rating must be between 1 and 5".into()));
    }
    Ok(())
}

pub async fn submit_worker_rating(
    state: &AppState,
    booking_id: &str,
    customer_user_id: &str,
    rating: i32,
) -> AppResult<Value> {
    validate_rating(rating)?;
    let bid = Uuid::parse_str(booking_id)?;
    let customer_id = Uuid::parse_str(customer_user_id)?;

    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        r#"SELECT status::text AS status, rating, "customerId", "operatorId"
           FROM bookings WHERE id = $1 FOR UPDATE"#,
    )
    .bind(bid)
    .fetch_optional(&mut tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.get::<Uuid, _>("customerId") != customer_id {
        return Err(AppError::NotFound("Booking not found".into()));
    }
    if row.get::<String, _>("status") != "COMPLETED" {
        return Err(AppError::BadRequest("Can only rate completed jobs".into()));
    }
    if row.get::<Option<i32>, _>("rating").is_some() {
        tx.commit().await?;
        return Ok(json!({ "message": "Rating submitted successfully" }));
    }

    sqlx::query(r#"UPDATE bookings SET rating = $1 WHERE id = $2"#)
        .bind(rating)
        .bind(bid)
        .execute(&mut tx)
        .await?;

    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();

    if let Some(op) = operator_id {
        update_worker_rating_average(&mut tx, op, rating).await?;
    }

    tx.commit().await?;

    if let Some(op) = operator_id {
        let _ = workers::refresh_worker_snapshot(state, &op.to_string()).await;
    }

    Ok(json!({ "message": "Rating submitted successfully" }))
}

async fn update_worker_rating_average(
    tx: &mut Transaction<'_, Postgres>,
    operator_id: Uuid,
    rating: i32,
) -> AppResult<()> {
    let profile_id: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM worker_profiles WHERE "userId" = $1 FOR UPDATE"#,
    )
    .bind(operator_id)
    .fetch_optional(&mut tx)
    .await?;

    let profile_id = match profile_id {
        Some(id) => id,
        None => return Ok(()),
    };

    let row = sqlx::query(
        r#"SELECT rating, "reviewCount" FROM worker_profiles WHERE id = $1"#,
    )
    .bind(profile_id)
    .fetch_one(&mut tx)
    .await?;

    let current_rating = row
        .try_get::<Option<rust_decimal::Decimal>, _>("rating")
        .ok()
        .flatten()
        .and_then(|d| d.to_f64())
        .unwrap_or(0.0);
    let review_count = row
        .try_get::<Option<i32>, _>("reviewCount")
        .ok()
        .flatten()
        .unwrap_or(0);
    let new_count = review_count + 1;
    let new_rating = (current_rating * review_count as f64 + rating as f64) / new_count as f64;

    sqlx::query(
        r#"UPDATE worker_profiles SET rating = $1, "reviewCount" = $2 WHERE id = $3"#,
    )
    .bind(new_rating)
    .bind(new_count)
    .bind(profile_id)
    .execute(&mut tx)
    .await?;

    Ok(())
}

pub async fn rate_customer(
    state: &AppState,
    booking_id: &str,
    operator_user_id: &str,
    rating: i32,
) -> AppResult<Value> {
    validate_rating(rating)?;
    let bid = Uuid::parse_str(booking_id)?;
    let operator_id = Uuid::parse_str(operator_user_id)?;

    let row = sqlx::query(
        r#"SELECT status::text AS status, "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten() != Some(operator_id) {
        return Err(AppError::BadRequest(
            "Only the assigned worker can rate this customer".into(),
        ));
    }
    if row.get::<String, _>("status") != "COMPLETED" {
        return Err(AppError::BadRequest("Can only rate completed jobs".into()));
    }

    sqlx::query(r#"UPDATE bookings SET "customerRating" = $1 WHERE id = $2"#)
        .bind(rating)
        .bind(bid)
        .execute(&state.db)
        .await?;

    Ok(json!({ "message": "Customer rating submitted" }))
}

pub async fn report_dispute(
    state: &AppState,
    booking_id: &str,
    user_id: &str,
    reason: &str,
) -> AppResult<Value> {
    let trimmed = reason.trim();
    if trimmed.is_empty() {
        return Err(AppError::BadRequest("reason is required".into()));
    }

    let bid = Uuid::parse_str(booking_id)?;
    let uid = Uuid::parse_str(user_id)?;

    let row = sqlx::query(
        r#"SELECT "customerId", "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    let customer_id = row.get::<Uuid, _>("customerId");
    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten();
    let is_customer = customer_id == uid;
    let is_operator = operator_id == Some(uid);
    if !is_customer && !is_operator {
        return Err(AppError::BadRequest(
            "Only participants of this booking can report it".into(),
        ));
    }

    let reporter_role = if is_customer { "CUSTOMER" } else { "WORKER" };
    sqlx::query(
        r#"UPDATE bookings SET
            "disputeReason" = $1,
            "disputeReporterRole" = $2,
            "disputedAt" = NOW()
           WHERE id = $3"#,
    )
    .bind(trimmed)
    .bind(reporter_role)
    .bind(bid)
    .execute(&state.db)
    .await?;

    Ok(json!({
        "success": true,
        "message": "Report submitted — our team will review it.",
    }))
}

#[derive(Deserialize)]
pub struct DisputesQuery {
    pub open: Option<String>,
    pub page: Option<String>,
    pub limit: Option<String>,
}

pub async fn list_disputes(
    state: &AppState,
    open_only: bool,
    page: i64,
    limit: i64,
) -> AppResult<Vec<Value>> {
    let offset = (page - 1).max(0) * limit;
    let rows = if open_only {
        sqlx::query(
            r#"SELECT b.id, b.skill, b.status::text AS status, b."disputeReason", b."disputeReporterRole",
                      b."disputedAt", b."disputeResolution", b."disputeResolvedAt",
                      b."customerId", b."operatorId", b."serviceLocation", b."createdAt",
                      c.name AS "customerName", o.name AS "operatorName"
               FROM bookings b
               LEFT JOIN users c ON c.id = b."customerId"
               LEFT JOIN users o ON o.id = b."operatorId"
               WHERE b."disputedAt" IS NOT NULL AND b."disputeResolvedAt" IS NULL
               ORDER BY b."disputedAt" DESC
               LIMIT $1 OFFSET $2"#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    } else {
        sqlx::query(
            r#"SELECT b.id, b.skill, b.status::text AS status, b."disputeReason", b."disputeReporterRole",
                      b."disputedAt", b."disputeResolution", b."disputeResolvedAt",
                      b."customerId", b."operatorId", b."serviceLocation", b."createdAt",
                      c.name AS "customerName", o.name AS "operatorName"
               FROM bookings b
               LEFT JOIN users c ON c.id = b."customerId"
               LEFT JOIN users o ON o.id = b."operatorId"
               WHERE b."disputedAt" IS NOT NULL
               ORDER BY b."disputedAt" DESC
               LIMIT $1 OFFSET $2"#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?
    };

    Ok(rows.iter().map(dispute_json).collect())
}

pub async fn resolve_dispute(
    state: &AppState,
    booking_id: &str,
    resolution: &str,
) -> AppResult<Value> {
    let trimmed = resolution.trim();
    if trimmed.is_empty() {
        return Err(AppError::BadRequest("resolution is required".into()));
    }

    let bid = Uuid::parse_str(booking_id)?;
    let row = sqlx::query(
        r#"SELECT "disputedAt", "customerId", "operatorId" FROM bookings WHERE id = $1"#,
    )
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Booking not found".into()))?;

    if row
        .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("disputedAt")
        .ok()
        .flatten()
        .is_none()
    {
        return Err(AppError::BadRequest("This booking has no dispute to resolve".into()));
    }

    sqlx::query(
        r#"UPDATE bookings SET "disputeResolution" = $1, "disputeResolvedAt" = NOW() WHERE id = $2"#,
    )
    .bind(trimmed)
    .bind(bid)
    .execute(&state.db)
    .await?;

    let customer_id = row.get::<Uuid, _>("customerId").to_string();
    let operator_id = row
        .try_get::<Option<Uuid>, _>("operatorId")
        .ok()
        .flatten()
        .map(|u| u.to_string());

    let party_ids: Vec<String> = [Some(customer_id), operator_id]
        .into_iter()
        .flatten()
        .collect();
    state
        .fcm
        .send_to_users(
            state,
            &party_ids,
            "Report resolved",
            "The Gixbee team reviewed the report on your booking.",
            Some(&[("type", "dispute_resolved"), ("bookingId", booking_id)]),
        )
        .await;

    Ok(dispute_json(
        &sqlx::query(
            r#"SELECT b.id, b.skill, b.status::text AS status, b."disputeReason", b."disputeReporterRole",
                      b."disputedAt", b."disputeResolution", b."disputeResolvedAt",
                      b."customerId", b."operatorId", b."serviceLocation", b."createdAt",
                      c.name AS "customerName", o.name AS "operatorName"
               FROM bookings b
               LEFT JOIN users c ON c.id = b."customerId"
               LEFT JOIN users o ON o.id = b."operatorId"
               WHERE b.id = $1"#,
        )
        .bind(bid)
        .fetch_one(&state.db)
        .await?,
    ))
}

fn dispute_json(row: &sqlx::postgres::PgRow) -> Value {
    let id = row.get::<Uuid, _>("id").to_string();
    json!({
        "id": id,
        "bookingId": id,
        "skill": row.get::<Option<String>, _>("skill"),
        "status": row.get::<String, _>("status"),
        "serviceLocation": row.get::<Option<String>, _>("serviceLocation"),
        "disputeReason": row.get::<Option<String>, _>("disputeReason"),
        "disputeReporterRole": row.get::<Option<String>, _>("disputeReporterRole"),
        "disputedAt": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("disputedAt").ok().flatten(),
        "disputeResolution": row.get::<Option<String>, _>("disputeResolution"),
        "disputeResolvedAt": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("disputeResolvedAt").ok().flatten(),
        "customerId": row.get::<Uuid, _>("customerId").to_string(),
        "operatorId": row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten().map(|u| u.to_string()),
        "customer": {
            "id": row.get::<Uuid, _>("customerId").to_string(),
            "name": row.get::<Option<String>, _>("customerName"),
        },
        "operator": row.try_get::<Option<Uuid>, _>("operatorId").ok().flatten().map(|op| json!({
            "id": op.to_string(),
            "name": row.get::<Option<String>, _>("operatorName"),
        })),
        "createdAt": row.try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("createdAt").ok().flatten(),
    })
}
