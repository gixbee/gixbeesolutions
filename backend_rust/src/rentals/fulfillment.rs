use super::*;
use chrono::{DateTime,Utc};
use rust_decimal::Decimal;

pub(super) async fn acknowledge(State(state):State<AppState>,user:AuthUser,Path((id,action)):Path<(String,String)>)->AppResult<Json<Value>> {
    change(&state,&user,&id,&action).await
}

pub(super) async fn change(state:&AppState,user:&AuthUser,id:&str,action:&str)->AppResult<Json<Value>> {
    let uid=Uuid::parse_str(&user.user_id)?;let id=Uuid::parse_str(id)?;
    let mut tx=state.db.begin().await?;
    let item=sqlx::query(r#"SELECT i.id,i."ownerId" FROM rental_items i JOIN rental_reservations r ON r."itemId"=i.id WHERE r.id=$1 FOR UPDATE OF i"#)
        .bind(id).fetch_optional(&mut *tx).await?.ok_or_else(||AppError::NotFound("Rental not found".into()))?;
    let r=sqlx::query(&format!("SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id=$1 FOR UPDATE"))
        .bind(id).fetch_one(&mut *tx).await?;
    let owner:Uuid=item.get("ownerId");let renter:Uuid=r.get("renterId");
    let is_owner=owner==uid;
    if !is_owner && renter!=uid {return Err(AppError::NotFound("Rental not found".into()));}
    let status=r.get::<String,_>("status");
    let timestamp=|key:&str|r.get::<Option<DateTime<Utc>>,_>(key).is_some();
    let returned=timestamp("ownerReturnedAt")&&timestamp("renterReturnedAt");
    let (column, counterpart_column, notification)=match action {
        "handover"=>{
            if !["CONFIRMED","ACTIVE"].contains(&status.as_str()) || returned {
                return Err(AppError::Conflict("Handover requires a confirmed rental".into()));
            }
            if r.get::<chrono::NaiveDateTime,_>("startTime")>Utc::now().naive_utc() || r.get::<chrono::NaiveDateTime,_>("endTime")<=Utc::now().naive_utc() {
                return Err(AppError::Conflict("Handover must take place within the reserved time".into()));
            }
            if is_owner {
                ("ownerHandedOverAt", "renterCollectedAt", "Confirm when you collect the rental.")
            } else {
                ("renterCollectedAt", "ownerHandedOverAt", "Confirm when you hand over the rental.")
            }
        },
        "return"=>{
            if !["CONFIRMED","ACTIVE"].contains(&status.as_str()) || (!timestamp("ownerHandedOverAt")&&!timestamp("renterCollectedAt")) {
                return Err(AppError::Conflict("The item has not been handed over".into()));
            }
            if is_owner {
                ("ownerReturnedAt", "renterReturnedAt", "Confirm that you returned the rental.")
            } else {
                ("renterReturnedAt", "ownerReturnedAt", "Confirm that you received the returned rental.")
            }
        },
        "payment"=>{
            if !["CONFIRMED","ACTIVE","RETURN_PENDING"].contains(&status.as_str()) {return Err(AppError::Conflict("Payment acknowledgement requires a confirmed rental".into()));}
            if is_owner {
                ("ownerPaidAt", "renterPaidAt", "Confirm your rental payment in the app.")
            } else {
                ("renterPaidAt", "ownerPaidAt", "Review the rental payment and confirm receipt.")
            }
        },
        "refund"=>{
            let paid=timestamp("ownerPaidAt")||timestamp("renterPaidAt");
            let breakdown:Value=r.get("priceBreakdown");
            let deposit=breakdown.get("deposit").and_then(|v|v.as_str().map(str::to_owned).or_else(||Some(v.to_string())))
                .and_then(|s|s.parse::<Decimal>().ok()).unwrap_or_default();
            if !paid || !(status=="CANCELLED" || (returned && deposit>Decimal::ZERO)) {
                return Err(AppError::Conflict("No recorded payment is due for refund yet".into()));
            }
            if is_owner {
                ("ownerRefundedAt", "renterRefundedAt", "Confirm once you receive your rental refund.")
            } else {
                ("renterRefundedAt", "ownerRefundedAt", "Review the refund and confirm on your side.")
            }
        },
        _=>return Err(AppError::BadRequest("Unknown rental acknowledgement".into())),
    };
    // The column comes only from the fixed allowlist above, never request text.
    sqlx::query(&format!(r#"UPDATE rental_reservations SET "{column}"=COALESCE("{column}",NOW()),"updatedAt"=NOW() WHERE id=$1"#))
        .bind(id).execute(&mut *tx).await?;
    sqlx::query(r#"UPDATE rental_reservations SET status='ACTIVE' WHERE id=$1 AND status='CONFIRMED'
        AND "ownerHandedOverAt" IS NOT NULL AND "renterCollectedAt" IS NOT NULL"#)
        .bind(id).execute(&mut *tx).await?;
    sqlx::query(r#"UPDATE rental_reservations SET status='RETURN_PENDING' WHERE id=$1 AND status IN ('CONFIRMED','ACTIVE')
        AND "ownerReturnedAt" IS NOT NULL AND "renterReturnedAt" IS NOT NULL"#)
        .bind(id).execute(&mut *tx).await?;
    sqlx::query(r#"UPDATE rental_reservations SET status='COMPLETED' WHERE id=$1 AND status IN ('ACTIVE','RETURN_PENDING')
        AND "ownerReturnedAt" IS NOT NULL AND "renterReturnedAt" IS NOT NULL
        AND "ownerPaidAt" IS NOT NULL AND "renterPaidAt" IS NOT NULL
        AND (COALESCE(("priceBreakdown"->>'deposit')::numeric,0)=0 OR ("ownerRefundedAt" IS NOT NULL AND "renterRefundedAt" IS NOT NULL))"#)
        .bind(id).execute(&mut *tx).await?;
    let counterpart = if is_owner { renter } else { owner };
    if counterpart != uid && !timestamp(column) && !timestamp(counterpart_column) {
        crate::outbox::notify(
            &mut tx,
            id,
            counterpart,
            "Rental confirmation needed",
            notification,
            json!({"type":"rental_status","reservationId":id,"audience":if is_owner {"renter"} else {"owner"}}),
        ).await?;
    }
    let row=sqlx::query(&format!("SELECT {RENTAL_RESERVATION_COLS} FROM rental_reservations WHERE id=$1"))
        .bind(id).fetch_one(&mut *tx).await?;
    tx.commit().await?;Ok(Json(reservation_json(&row)))
}
