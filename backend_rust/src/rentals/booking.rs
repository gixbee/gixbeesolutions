use super::{reservation_json_view, ReservationView};
use crate::common::pg::RENTAL_RESERVATION_COLS;
use axum::{
    extract::{Path, State},
    Json,
};
use chrono::{DateTime, Duration, Utc};
use rand::Rng;
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub const HOLD_MINUTES: i64 = 10;

pub fn advance_due(listed: Decimal, percent: Decimal, total: Decimal) -> Decimal {
    if total <= Decimal::ZERO {
        return Decimal::ZERO;
    }
    let listed = if listed < Decimal::ZERO {
        Decimal::ZERO
    } else {
        listed.round_dp(2)
    };
    if listed > Decimal::ZERO {
        return listed.min(total);
    }
    let percent = if percent < Decimal::ZERO {
        Decimal::ZERO
    } else {
        percent.min(Decimal::from(100))
    };
    if percent > Decimal::ZERO {
        let cut = (total * percent / Decimal::from(100)).round_dp(2);
        return cut.max(Decimal::ONE.min(total)).min(total);
    }
    let twenty = (total * Decimal::new(2, 1)).round_dp(2);
    let floor = if twenty < Decimal::ONE {
        Decimal::ONE.min(total)
    } else {
        twenty
    };
    floor.min(total)
}

pub fn otp() -> String {
    format!("{:04}", rand::thread_rng().gen_range(0..10_000))
}

pub fn hold_deadline(now: DateTime<Utc>) -> DateTime<Utc> {
    now + Duration::minutes(HOLD_MINUTES)
}

/// Releases expired temp holds so the units return to the catalog.
pub async fn expire_holds(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
) -> AppResult<()> {
    sqlx::query(
        r#"UPDATE rental_reservations
           SET status = 'CANCELLED'::rental_reservations_status_enum,
               "paymentStatus" = 'EXPIRED',
               "updatedAt" = NOW()
           WHERE status::text IN ('TEMP_HOLD','PAYMENT_PENDING')
             AND "holdExpiresAt" IS NOT NULL
             AND "holdExpiresAt" < NOW()"#,
    )
    .execute(&mut **tx)
    .await?;
    Ok(())
}

pub fn gateway_configured(state: &AppState) -> bool {
    crate::config::is_real_secret(state.config.razorpay_key_id.as_deref())
        && crate::config::is_real_secret(state.config.razorpay_key_secret.as_deref())
}

#[derive(Deserialize)]
pub(super) struct OtpBody {
    kind: String,
    code: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SettleBody {
    #[serde(default)]
    late_fee: f64,
    #[serde(default)]
    damage_amount: f64,
}

pub async fn advance_order(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&res_id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    expire_holds(&mut tx).await?;
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1 FOR UPDATE"#
    ))
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Reservation not found".into()))?;
    if row.get::<Uuid, _>("renterId") != uid {
        return Err(AppError::Forbidden(
            "You cannot pay for this rental".into(),
        ));
    }
    let status = row.get::<String, _>("status");
    if !matches!(status.as_str(), "TEMP_HOLD" | "PAYMENT_PENDING") {
        return Err(AppError::Conflict(
            "This rental is not waiting for an advance payment".into(),
        ));
    }
    if row
        .try_get::<Option<DateTime<Utc>>, _>("holdExpiresAt")
        .ok()
        .flatten()
        .is_some_and(|d| d < Utc::now())
    {
        return Err(AppError::Conflict(
            "This hold expired. Start a new reservation.".into(),
        ));
    }
    let advance = row
        .try_get::<Decimal, _>("advanceAmount")
        .unwrap_or(Decimal::ZERO)
        .trunc();
    let rupees = advance.to_i32().unwrap_or(0);
    if rupees < 1 {
        return Err(AppError::BadRequest(
            "No advance is due on this rental".into(),
        ));
    }
    sqlx::query(
        r#"UPDATE rental_reservations
           SET status = 'PAYMENT_PENDING'::rental_reservations_status_enum,
               "paymentStatus" = 'PAYMENT_PENDING',
               "updatedAt" = NOW()
           WHERE id = $1"#,
    )
    .bind(rid)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    crate::payments::create_razorpay_order(
        &state,
        &user.user_id,
        crate::payments::PURPOSE_RENTAL_ADVANCE,
        rupees,
        Some(json!({ "reservationId": rid })),
    )
    .await
}

pub async fn verify_otp(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
    Json(body): Json<OtpBody>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&res_id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let kind = body.kind.trim().to_ascii_lowercase();
    let code = body.code.trim();
    if code.len() != 4 || !code.chars().all(|c| c.is_ascii_digit()) {
        return Err(AppError::BadRequest("Enter the 4-digit OTP".into()));
    }
    if !matches!(kind.as_str(), "handover" | "return") {
        return Err(AppError::BadRequest("Unknown rental OTP".into()));
    }
    let mut tx = state.db.begin().await?;
    let item = sqlx::query(
        r#"SELECT i.id, i."ownerId" FROM rental_items i
           JOIN rental_reservations r ON r."itemId" = i.id
           WHERE r.id = $1 FOR UPDATE OF i"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Reservation not found".into()))?;
    if item.get::<Uuid, _>("ownerId") != uid {
        return Err(AppError::Forbidden(
            "Only the rental store can verify this OTP".into(),
        ));
    }
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1 FOR UPDATE"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    let status = row.get::<String, _>("status");
    let expected = if kind == "handover" {
        row.try_get::<Option<String>, _>("handoverOtp")
            .ok()
            .flatten()
    } else {
        row.try_get::<Option<String>, _>("returnOtp")
            .ok()
            .flatten()
    };
    if expected.as_deref() != Some(code) {
        return Err(AppError::Forbidden("That OTP does not match".into()));
    }
    if kind == "handover" {
        if status != "CONFIRMED" {
            return Err(AppError::Conflict(
                "Handover OTP is for a confirmed rental".into(),
            ));
        }
        sqlx::query(
            r#"UPDATE rental_reservations
               SET "ownerHandedOverAt" = COALESCE("ownerHandedOverAt", NOW()),
                   "renterCollectedAt" = COALESCE("renterCollectedAt", NOW()),
                   status = 'ACTIVE'::rental_reservations_status_enum,
                   "updatedAt" = NOW()
               WHERE id = $1"#,
        )
        .bind(rid)
        .execute(&mut *tx)
        .await?;
    } else {
        if !matches!(status.as_str(), "ACTIVE" | "CONFIRMED") {
            return Err(AppError::Conflict(
                "Return OTP is for an active rental".into(),
            ));
        }
        sqlx::query(
            r#"UPDATE rental_reservations
               SET "ownerReturnedAt" = COALESCE("ownerReturnedAt", NOW()),
                   "renterReturnedAt" = COALESCE("renterReturnedAt", NOW()),
                   status = 'RETURN_PENDING'::rental_reservations_status_enum,
                   "updatedAt" = NOW()
               WHERE id = $1"#,
        )
        .bind(rid)
        .execute(&mut *tx)
        .await?;
    }
    if kind == "return" && row.get::<Option<DateTime<Utc>>, _>("renterPaidAt").is_none() {
        crate::outbox::notify(
            &mut tx,
            rid,
            row.get("renterId"),
            "Rental settlement needed",
            "Return OTP verified. Complete settlement to close the rental.",
            json!({"type":"rental_status","reservationId":rid,"audience":"renter"}),
        )
        .await?;
    }
    let out = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(reservation_json_view(
        &out,
        Some(ReservationView::Owner),
    )))
}

pub async fn settle(
    State(state): State<AppState>,
    user: AuthUser,
    Path(res_id): Path<String>,
    Json(body): Json<SettleBody>,
) -> AppResult<Json<Value>> {
    let rid = Uuid::parse_str(&res_id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    if !(0.0..=99_999_999.0).contains(&body.late_fee)
        || !(0.0..=99_999_999.0).contains(&body.damage_amount)
    {
        return Err(AppError::BadRequest("Settlement amounts are invalid".into()));
    }
    let late = Decimal::from_f64_retain(body.late_fee)
        .unwrap_or(Decimal::ZERO)
        .round_dp(2);
    let damage = Decimal::from_f64_retain(body.damage_amount)
        .unwrap_or(Decimal::ZERO)
        .round_dp(2);
    let mut tx = state.db.begin().await?;
    let item = sqlx::query(
        r#"SELECT i."ownerId" FROM rental_items i
           JOIN rental_reservations r ON r."itemId" = i.id
           WHERE r.id = $1 FOR UPDATE OF i"#,
    )
    .bind(rid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Reservation not found".into()))?;
    if item.get::<Uuid, _>("ownerId") != uid {
        return Err(AppError::Forbidden(
            "Only the rental store can settle this booking".into(),
        ));
    }
    let row = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1 FOR UPDATE"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    let status = row.get::<String, _>("status");
    if !matches!(status.as_str(), "ACTIVE" | "RETURN_PENDING") {
        return Err(AppError::Conflict(
            "Settlement is available after handover".into(),
        ));
    }
    let total = row
        .try_get::<Decimal, _>("totalPrice")
        .unwrap_or(Decimal::ZERO);
    let advance = row
        .try_get::<Decimal, _>("advanceAmount")
        .unwrap_or(Decimal::ZERO);
    let remaining = (total - advance + late + damage).max(Decimal::ZERO).round_dp(2);
    sqlx::query(
        r#"UPDATE rental_reservations
           SET "lateFee" = $1, "damageAmount" = $2, "remainingAmount" = $3, "updatedAt" = NOW()
           WHERE id = $4"#,
    )
    .bind(late)
    .bind(damage)
    .bind(remaining)
    .bind(rid)
    .execute(&mut *tx)
    .await?;
    let out = sqlx::query(&format!(
        r#"SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id = $1"#
    ))
    .bind(rid)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(reservation_json_view(
        &out,
        Some(ReservationView::Owner),
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn twenty_percent_floor_when_the_store_did_not_set_an_advance() {
        assert_eq!(
            advance_due(Decimal::ZERO, Decimal::ZERO, Decimal::from(1000)),
            Decimal::from(200)
        );
        assert_eq!(
            advance_due(Decimal::from(50), Decimal::ZERO, Decimal::from(1000)),
            Decimal::from(50)
        );
        assert_eq!(
            advance_due(Decimal::from(5000), Decimal::ZERO, Decimal::from(1000)),
            Decimal::from(1000)
        );
        assert_eq!(advance_due(Decimal::ZERO, Decimal::ZERO, Decimal::ZERO), Decimal::ZERO);
        assert_eq!(advance_due(Decimal::ZERO, Decimal::ZERO, Decimal::new(4, 0)), Decimal::ONE);
        assert_eq!(
            advance_due(Decimal::ZERO, Decimal::from(10), Decimal::from(1000)),
            Decimal::from(100)
        );
    }

    #[test]
    fn otp_is_always_four_digits() {
        for _ in 0..20 {
            let code = otp();
            assert_eq!(code.len(), 4);
            assert!(code.chars().all(|c| c.is_ascii_digit()));
        }
    }
}
