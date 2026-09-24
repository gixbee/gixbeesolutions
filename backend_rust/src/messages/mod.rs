use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/conversations", get(list_conversations))
        .route("/thread/{userId}", get(get_thread))
        .route("/", post(send_message))
}

async fn list_conversations(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        r#"
        SELECT DISTINCT ON (partner_id)
            partner_id,
            partner_name,
            partner_phone,
            body,
            "createdAt",
            unread
        FROM (
            SELECT
                CASE WHEN m."senderId" = $1 THEN m."recipientId" ELSE m."senderId" END AS partner_id,
                u.name AS partner_name,
                u."phoneNumber" AS partner_phone,
                m.body,
                m."createdAt",
                (m."recipientId" = $1 AND NOT m."isRead")::int AS unread
            FROM messages m
            JOIN users u ON u.id = CASE WHEN m."senderId" = $1 THEN m."recipientId" ELSE m."senderId" END
            WHERE m."senderId" = $1 OR m."recipientId" = $1
        ) sub
        ORDER BY partner_id, "createdAt" DESC
        "#,
    )
    .bind(uid)
    .fetch_all(&state.db)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for r in &rows {
        let partner = r.get::<Uuid, _>("partner_id");
        let shared = contact_shared(&state, uid, partner).await;
        out.push(json!({
            "userId": partner.to_string(),
            "name": r.get::<Option<String>, _>("partner_name"),
            "phoneNumber": phone_if_shared(r.get::<Option<String>, _>("partner_phone"), shared),
            "lastMessage": r.get::<String, _>("body"),
            "lastAt": r.try_get::<chrono::DateTime<chrono::Utc>, _>("createdAt").ok(),
            "unread": r.get::<i32, _>("unread"),
        }));
    }
    Ok(Json(out))
}

fn phone_if_shared(phone: Option<String>, unlocked: bool) -> Option<String> {
    if unlocked { phone.filter(|value| !value.is_empty()) } else { None }
}

async fn contact_shared(state: &AppState, left: Uuid, right: Uuid) -> bool {
    sqlx::query_scalar(
        r#"SELECT EXISTS(
            SELECT 1 FROM hiring_interests hi
            JOIN hiring_requests hr ON hr.id = hi."requestId"
            WHERE (
              (hi."candidateId" = $1 AND hr."employerId" = $2)
              OR (hi."candidateId" = $2 AND hr."employerId" = $1)
            )
            AND (
              hi.decision::text = 'HIRED'
              OR COALESCE(hi.progress->>'contactShared', 'false') = 'true'
            )
        )"#,
    )
    .bind(left)
    .bind(right)
    .fetch_one(&state.db)
    .await
    .unwrap_or(false)
}

async fn get_thread(
    State(state): State<AppState>,
    user: AuthUser,
    Path(other_id): Path<String>,
) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let oid = Uuid::parse_str(&other_id)?;
    sqlx::query(
        r#"UPDATE messages SET "isRead" = true WHERE "senderId" = $2 AND "recipientId" = $1 AND "isRead" = false"#,
    )
    .bind(uid)
    .bind(oid)
    .execute(&state.db)
    .await?;

    let rows = sqlx::query(
        r#"SELECT id, "senderId", "recipientId", body, "bookingId", "isRead", "createdAt"
           FROM messages
           WHERE ("senderId" = $1 AND "recipientId" = $2) OR ("senderId" = $2 AND "recipientId" = $1)
           ORDER BY "createdAt""#,
    )
    .bind(uid)
    .bind(oid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(message_dto).collect()))
}

#[derive(Deserialize)]
struct SendBody {
    recipientId: String,
    body: String,
    bookingId: Option<String>,
}

async fn send_message(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<SendBody>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rid = Uuid::parse_str(&body.recipientId)?;
    let exists = sqlx::query_scalar::<_, i64>(r#"SELECT COUNT(*) FROM users WHERE id = $1"#)
        .bind(rid)
        .fetch_one(&state.db)
        .await?;
    if exists == 0 {
        return Err(AppError::NotFound("Recipient not found".into()));
    }
    let allowed: bool = sqlx::query_scalar(
        r#"SELECT
            EXISTS(SELECT 1 FROM messages WHERE ("senderId"=$1 AND "recipientId"=$2) OR ("senderId"=$2 AND "recipientId"=$1))
            OR EXISTS(SELECT 1 FROM bookings WHERE ("customerId"=$1 AND "operatorId"=$2) OR ("customerId"=$2 AND "operatorId"=$1))
            OR EXISTS(
              SELECT 1 FROM hiring_interests hi
              JOIN hiring_requests hr ON hr.id = hi."requestId"
              WHERE hi.response::text = 'INTERESTED' AND hi.decision::text <> 'REJECTED'
                AND ((hi."candidateId"=$1 AND hr."employerId"=$2) OR (hi."candidateId"=$2 AND hr."employerId"=$1))
            )
            OR EXISTS(
              SELECT 1 FROM job_applications a
              JOIN job_posts j ON j.id = a."jobPostId"
              WHERE a.status::text <> 'WITHDRAWN'
                AND ((a."applicantId"=$1 AND j."employerId"=$2) OR (a."applicantId"=$2 AND j."employerId"=$1))
            )
            OR EXISTS(
              SELECT 1 FROM matching_events e
              JOIN job_posts j ON j.id = e."jobPostId"
              WHERE e."eventType" = 'EMPLOYER_INVITE'
                AND ((e."candidateId"=$1 AND j."employerId"=$2) OR (e."candidateId"=$2 AND j."employerId"=$1))
            )"#,
    )
    .bind(uid)
    .bind(rid)
    .fetch_one(&state.db)
    .await?;
    if !allowed {
        return Err(AppError::Forbidden("You can only message someone you already work with".into()));
    }

    let id = Uuid::new_v4();
    let booking_id = body.bookingId.as_ref().and_then(|b| Uuid::parse_str(b).ok());
    let content = body.body.trim();
    sqlx::query(
        r#"INSERT INTO messages (id, "senderId", "recipientId", body, "bookingId", "isRead") VALUES ($1, $2, $3, $4, $5, false)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(rid)
    .bind(content)
    .bind(booking_id)
    .execute(&state.db)
    .await?;

    let dto = message_dto(
        &sqlx::query(
            r#"SELECT id, "senderId", "recipientId", body, "bookingId", "isRead", "createdAt" FROM messages WHERE id = $1"#,
        )
        .bind(id)
        .fetch_one(&state.db)
        .await?,
    );

    state
        .realtime
        .emit_to_user(&body.recipientId, "new_message", &dto)
        .await;

    Ok(Json(dto))
}

fn message_dto(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "body": row.get::<String, _>("body"),
        "bookingId": row.try_get::<Option<Uuid>, _>("bookingId").ok().flatten().map(|u| u.to_string()),
        "isRead": row.get::<bool, _>("isRead"),
        "createdAt": row.get::<chrono::DateTime<chrono::Utc>, _>("createdAt"),
        "senderId": row.get::<Uuid, _>("senderId").to_string(),
        "recipientId": row.get::<Uuid, _>("recipientId").to_string(),
    })
}

#[cfg(test)]
mod tests {
    #[test]
    fn phone_stays_hidden_until_contact_is_shared() {
        assert!(super::phone_if_shared(Some("999".into()), false).is_none());
        assert_eq!(super::phone_if_shared(Some("999".into()), true).as_deref(), Some("999"));
    }
}
