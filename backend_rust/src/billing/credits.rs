use sqlx::{Postgres, Transaction};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::state::AppState;

const JOB_CREDIT_PER_ACCEPT_KEY: &str = "job_credit_per_accept";
const JOB_CREDIT_PER_ACCEPT_FALLBACK: i32 = 15;

pub async fn get_credits_per_accept(state: &AppState) -> i32 {
    let raw: Option<String> = sqlx::query_scalar(
        r#"SELECT value FROM master_entries
           WHERE type::text = 'CONFIGURATION' AND label = $1 AND "isActive" = true
           LIMIT 1"#,
    )
    .bind(JOB_CREDIT_PER_ACCEPT_KEY)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    match raw {
        Some(s) => {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return JOB_CREDIT_PER_ACCEPT_FALLBACK;
            }
            trimmed
                .parse::<i32>()
                .ok()
                .filter(|n| *n >= 0)
                .unwrap_or(JOB_CREDIT_PER_ACCEPT_FALLBACK)
        }
        None => JOB_CREDIT_PER_ACCEPT_FALLBACK,
    }
}

/// Deduct pack credits on accept. Returns remaining balance after deduction.
pub async fn consume_credit(
    state: &AppState,
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    booking_id: Uuid,
) -> AppResult<i32> {
    let cost = get_credits_per_accept(state).await;
    if cost == 0 {
        let balance = sqlx::query_scalar::<_, i32>(
            r#"SELECT balance FROM job_credits WHERE "userId" = $1"#,
        )
        .bind(user_id)
        .fetch_optional(&mut tx)
        .await?
        .unwrap_or(0);
        return Ok(balance);
    }

    let balance = sqlx::query_scalar::<_, i32>(
        r#"SELECT balance FROM job_credits WHERE "userId" = $1 FOR UPDATE"#,
    )
    .bind(user_id)
    .fetch_optional(&mut tx)
    .await?
    .unwrap_or(0);

    if balance < cost {
        return Err(AppError::BadRequest(
            "No job credits left. Buy a pack to continue.".into(),
        ));
    }

    let new_balance = balance - cost;
    sqlx::query(r#"UPDATE job_credits SET balance = $1 WHERE "userId" = $2"#)
        .bind(new_balance)
        .bind(user_id)
        .execute(&mut tx)
        .await?;

    sqlx::query(
        r#"INSERT INTO credit_transactions (id, "userId", delta, reason, "bookingId")
           VALUES ($1, $2, $3, 'JOB_ACCEPTED', $4)"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(-cost)
    .bind(booking_id)
    .execute(&mut tx)
    .await?;

    Ok(new_balance)
}

/// Refund job credits consumed on accept (idempotent per reason).
pub async fn refund_credit(
    tx: &mut Transaction<'_, Postgres>,
    user_id: Uuid,
    booking_id: Uuid,
    reason: &str,
) -> AppResult<()> {
    let existing: Option<i32> = sqlx::query_scalar(
        r#"SELECT 1 FROM credit_transactions
           WHERE "userId" = $1 AND "bookingId" = $2 AND reason = $3 LIMIT 1"#,
    )
    .bind(user_id)
    .bind(booking_id)
    .bind(reason)
    .fetch_optional(&mut tx)
    .await?;
    if existing.is_some() {
        return Ok(());
    }

    let accept_delta: Option<i32> = sqlx::query_scalar(
        r#"SELECT delta FROM credit_transactions
           WHERE "userId" = $1 AND "bookingId" = $2 AND reason = 'JOB_ACCEPTED'
           ORDER BY "createdAt" DESC LIMIT 1"#,
    )
    .bind(user_id)
    .bind(booking_id)
    .fetch_optional(&mut tx)
    .await?;

    let amount = accept_delta
        .map(|d| d.abs())
        .unwrap_or(JOB_CREDIT_PER_ACCEPT_FALLBACK);
    if amount == 0 {
        return Ok(());
    }

    let balance = sqlx::query_scalar::<_, i32>(
        r#"SELECT balance FROM job_credits WHERE "userId" = $1 FOR UPDATE"#,
    )
    .bind(user_id)
    .fetch_optional(&mut tx)
    .await?
    .unwrap_or(0);

    sqlx::query(r#"UPDATE job_credits SET balance = $1 WHERE "userId" = $2"#)
        .bind(balance + amount)
        .bind(user_id)
        .execute(&mut tx)
        .await?;

    sqlx::query(
        r#"INSERT INTO credit_transactions (id, "userId", delta, reason, "bookingId")
           VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(amount)
    .bind(reason)
    .bind(booking_id)
    .execute(&mut tx)
    .await?;

    Ok(())
}
