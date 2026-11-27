use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::{PgConnection, Row};
use uuid::Uuid;

use crate::{
    error::{AppError, AppResult},
    master_admin::plan_value,
    middleware::auth::AuthUser,
    state::AppState,
};

pub const PURPOSE: &str = "PLATFORM_PLAN";

#[derive(Clone, Copy)]
struct Plan {
    code: &'static str,
    family: &'static str,
    tier: &'static str,
    name: &'static str,
    price: &'static str,
    days: &'static str,
    limit: Option<&'static str>,
}

const PLANS: &[Plan] = &[
    Plan {
        code: "career_month",
        family: "CAREER",
        tier: "PRO",
        name: "Pro monthly",
        price: "seeker_pro_month",
        days: "seeker_pro_month_days",
        limit: None,
    },
    Plan {
        code: "career_quarter",
        family: "CAREER",
        tier: "PRO",
        name: "Pro quarterly",
        price: "seeker_pro_quarter",
        days: "seeker_pro_quarter_days",
        limit: None,
    },
    Plan {
        code: "service_standard",
        family: "SERVICE",
        tier: "STANDARD",
        name: "Standard",
        price: "service_standard",
        days: "business_plan_days",
        limit: Some("service_standard_limit"),
    },
    Plan {
        code: "service_pro",
        family: "SERVICE",
        tier: "PRO",
        name: "Pro",
        price: "service_pro",
        days: "business_plan_days",
        limit: None,
    },
    Plan {
        code: "rental_standard",
        family: "RENTAL",
        tier: "STANDARD",
        name: "Standard",
        price: "rental_standard",
        days: "business_plan_days",
        limit: None,
    },
    Plan {
        code: "shop_standard",
        family: "SHOP",
        tier: "STANDARD",
        name: "Standard",
        price: "shop_standard",
        days: "business_plan_days",
        limit: None,
    },
    Plan {
        code: "hiring_standard",
        family: "HIRING",
        tier: "STANDARD",
        name: "Standard",
        price: "hiring_standard",
        days: "business_plan_days",
        limit: None,
    },
];

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/career/trial", post(trial))
        .route("/{family}", get(catalogue))
        .route("/checkout/{code}", post(checkout))
}

fn allowance(family: &str) -> AppResult<Option<&'static str>> {
    match family {
        "CAREER" => Ok(None),
        "SERVICE" => Ok(Some("service_basic_limit")),
        "RENTAL" => Ok(Some("rental_basic_limit")),
        "SHOP" => Ok(Some("shop_basic_limit")),
        "HIRING" => Ok(Some("hiring_basic_limit")),
        _ => Err(AppError::NotFound("Unknown plan category".into())),
    }
}

async fn catalogue(
    State(state): State<AppState>,
    user: AuthUser,
    Path(family): Path<String>,
) -> AppResult<Json<Value>> {
    let base_limit = match allowance(&family)? {
        Some(key) => plan_value(&state.db, key).await?,
        None => 2,
    };
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(
        "SELECT tier, MAX(valid_until) AS expiry FROM platform_plan_grants
         WHERE user_id=$1 AND family=$2 AND valid_until>NOW() GROUP BY tier ORDER BY tier",
    )
    .bind(uid)
    .bind(&family)
    .fetch_all(&state.db)
    .await?;
    let active: Vec<Value> = rows
        .iter()
        .map(|row| {
            json!({
                "tier":row.get::<String,_>("tier"),
                "validUntil":row.get::<chrono::DateTime<chrono::Utc>,_>("expiry"),
            })
        })
        .collect();
    let pro_active = rows.iter().any(|row| row.get::<String, _>("tier") == "PRO");
    let expiry_by_tier: std::collections::HashMap<String, chrono::DateTime<chrono::Utc>> = rows
        .iter()
        .map(|row| {
            (
                row.get::<String, _>("tier"),
                row.get::<chrono::DateTime<chrono::Utc>, _>("expiry"),
            )
        })
        .collect();
    let mut plans = Vec::new();
    for plan in PLANS.iter().filter(|plan| plan.family == family) {
        let (price, snapshot) = quote(&state, *plan).await?;
        if price <= 0 {
            continue;
        }
        let (action, hint) = plan_offer_action(plan.tier, &expiry_by_tier, pro_active);
        plans.push(json!({
            "code": plan.code,
            "name": plan.name,
            "tier": plan.tier,
            "price": price,
            "days": snapshot["days"],
            "capacity": snapshot["capacity"],
            "action": action,
            "hint": hint,
        }));
    }
    let mut trial_days = 0;
    if family == "CAREER" && active.is_empty() {
        let used: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM platform_plan_grants WHERE user_id=$1 AND family='CAREER')")
            .bind(uid).fetch_one(&state.db).await?;
        if !used {
            trial_days = plan_value(&state.db, "seeker_trial_days").await?;
        }
    }
    Ok(Json(
        json!({
            "plans": plans,
            "basicCapacity": base_limit,
            "active": active,
            "trialDays": trial_days,
            "renewWindowDays": 7,
        }),
    ))
}

fn plan_offer_action(
    tier: &str,
    expiry_by_tier: &std::collections::HashMap<String, chrono::DateTime<chrono::Utc>>,
    pro_active: bool,
) -> (&'static str, String) {
    if tier == "STANDARD" && pro_active {
        return (
            "included",
            "Pro is already active, so Standard is included.".into(),
        );
    }
    if let Some(until) = expiry_by_tier.get(tier) {
        let renew_from = *until - chrono::Duration::days(7);
        if chrono::Utc::now() < renew_from {
            return (
                "active",
                format!(
                    "Already active until {}. Renew in the last 7 days.",
                    until.format("%d/%m/%Y %H:%M")
                ),
            );
        }
        return (
            "renew",
            format!(
                "Renew to extend past {}.",
                until.format("%d/%m/%Y %H:%M")
            ),
        );
    }
    ("buy", String::new())
}

async fn quote(state: &AppState, plan: Plan) -> AppResult<(i32, Value)> {
    let price = plan_value(&state.db, plan.price).await?;
    let days = plan_value(&state.db, plan.days).await?;
    let capacity = match plan.limit {
        Some(key) => plan_value(&state.db, key).await?,
        None => 0,
    };
    Ok((
        price,
        json!({"planCode":plan.code,"planName":plan.name,"family":plan.family,
        "tier":plan.tier,"days":days,"capacity":capacity}),
    ))
}

async fn checkout(
    State(state): State<AppState>,
    user: AuthUser,
    Path(code): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let plan = PLANS
        .iter()
        .find(|plan| plan.code == code)
        .ok_or_else(|| AppError::NotFound("Plan not found".into()))?;
    if plan.family != "CAREER" {
        let verified: bool = sqlx::query_scalar(
            r#"SELECT EXISTS(SELECT 1 FROM businesses
                WHERE "ownerId"=$1 AND type::text=$2 AND status::text='VERIFIED')"#,
        )
        .bind(Uuid::parse_str(&user.user_id)?)
        .bind(plan.family)
        .fetch_one(&state.db)
        .await?;
        if !verified {
            return Err(AppError::Conflict(
                "Verify a business in this category before buying a plan.".into(),
            ));
        }
    }
    let (price, snapshot) = quote(&state, *plan).await?;
    if price <= 0
        || body["price"].as_i64() != Some(i64::from(price))
        || body["days"] != snapshot["days"]
        || body["capacity"] != snapshot["capacity"]
    {
        return Err(AppError::Conflict(
            "Plan details changed. Reopen Plans to see the current offer.".into(),
        ));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    // Block same-tier repurchase while the grant still has more than 7 days left.
    // Within that window, checkout is treated as a renewal that extends validity.
    let active_until: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar(
        "SELECT MAX(valid_until) FROM platform_plan_grants
         WHERE user_id=$1 AND family=$2 AND tier=$3 AND valid_until>NOW()",
    )
    .bind(uid)
    .bind(plan.family)
    .bind(plan.tier)
    .fetch_one(&state.db)
    .await?;
    if let Some(until) = active_until {
        let renew_from = until - chrono::Duration::days(7);
        if chrono::Utc::now() < renew_from {
            return Err(AppError::Conflict(format!(
                "Your {} plan is already active until {}. Renew in the last 7 days.",
                plan.name,
                until.format("%d/%m/%Y %H:%M")
            )));
        }
    }
    // Pro already covers Standard capacity — don't sell Standard while Pro is live.
    if plan.tier == "STANDARD" {
        let pro_active: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM platform_plan_grants
             WHERE user_id=$1 AND family=$2 AND tier='PRO' AND valid_until>NOW())",
        )
        .bind(uid)
        .bind(plan.family)
        .fetch_one(&state.db)
        .await?;
        if pro_active {
            return Err(AppError::Conflict(
                "Pro is already active for this category, so Standard is included.".into(),
            ));
        }
    }
    crate::payments::create_razorpay_order(&state, &user.user_id, PURPOSE, price, Some(snapshot))
        .await
}

async fn trial(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Value>> {
    let days = plan_value(&state.db, "seeker_trial_days").await?;
    if days <= 0 {
        return Err(AppError::Conflict("Trial is unavailable".into()));
    }
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    lock_account(&mut tx, uid).await?;
    let used: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM platform_plan_grants WHERE user_id=$1 AND family='CAREER')",
    )
    .bind(uid)
    .fetch_one(&mut *tx)
    .await?;
    if used {
        return Err(AppError::Conflict(
            "Trial is only available before your first Pro plan".into(),
        ));
    }
    sqlx::query(
        "INSERT INTO platform_plan_grants (id,user_id,family,tier,plan_code,capacity,valid_until)
        VALUES ($1,$2,'CAREER','PRO','career_trial',0,NOW()+make_interval(days => $3))",
    )
    .bind(Uuid::new_v4())
    .bind(uid)
    .bind(days)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    catalogue(State(state), user, Path("CAREER".into())).await
}

pub async fn lock_account(db: &mut PgConnection, uid: Uuid) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>("SELECT id FROM users WHERE id=$1 FOR UPDATE")
        .bind(uid)
        .fetch_one(db)
        .await?;
    Ok(())
}

pub async fn capacity(db: &mut PgConnection, uid: Uuid, family: &str) -> AppResult<Option<i32>> {
    Ok(sqlx::query_scalar(
        "SELECT capacity FROM platform_plan_grants
        WHERE user_id=$1 AND family=$2 AND valid_until>NOW()
        ORDER BY (capacity=0) DESC, capacity DESC LIMIT 1",
    )
    .bind(uid)
    .bind(family)
    .fetch_optional(db)
    .await?)
}

pub async fn fulfil(state: &AppState, user_id: &str, order: Uuid, meta: &Value) -> AppResult<()> {
    let field = |key: &str| {
        meta[key]
            .as_str()
            .ok_or_else(|| AppError::Internal("Missing plan order details".into()))
    };
    let days = meta["days"]
        .as_i64()
        .filter(|d| (1..=365).contains(d))
        .ok_or_else(|| AppError::Internal("Invalid plan duration".into()))? as i32;
    let capacity = meta["capacity"]
        .as_i64()
        .filter(|c| (0..=1000).contains(c))
        .ok_or_else(|| AppError::Internal("Invalid plan capacity".into()))?
        as i32;
    let uid = Uuid::parse_str(user_id)?;
    let mut tx = state.db.begin().await?;
    lock_account(&mut tx, uid).await?;
    sqlx::query("INSERT INTO platform_plan_grants (id,user_id,payment_order_id,family,tier,plan_code,capacity,valid_until)
        SELECT $1,$2,$3,$4,$5,$6,$7,GREATEST(NOW(),MAX(valid_until))+make_interval(days => $8)
        FROM platform_plan_grants WHERE user_id=$2 AND family=$4 AND tier=$5
        ON CONFLICT (payment_order_id) DO NOTHING")
        .bind(Uuid::new_v4()).bind(uid).bind(order).bind(field("family")?).bind(field("tier")?)
        .bind(field("planCode")?).bind(capacity).bind(days).execute(&mut *tx).await?;
    tx.commit().await?;
    Ok(())
}

pub fn check_limit(count: i64, capacity: i32) -> AppResult<()> {
    if capacity > 0 && count >= i64::from(capacity) {
        return Err(AppError::Conflict(
            "Your current plan has reached its limit. Open Plans to see upgrade options.".into(),
        ));
    }
    Ok(())
}

pub async fn check_hiring_limit(
    db: &mut PgConnection,
    uid: Uuid,
    business: Uuid,
    basic: i32,
) -> AppResult<()> {
    let limit = capacity(db, uid, "HIRING").await?.unwrap_or(basic);
    if limit == 0 {
        return Ok(());
    }
    let count: i64 = sqlx::query_scalar(
        r#"SELECT
            (SELECT COUNT(*) FROM hiring_requests WHERE "businessId"=$1
               AND status::text='COLLECTING' AND "deadlineAt">NOW())
          + (SELECT COUNT(*) FROM payment_orders WHERE "userId"=$2
               AND purpose::text='HIRING_MATCH_FEE' AND status='CREATED'
               AND meta->>'businessId'=$1::uuid::text
               AND "createdAt">NOW()-INTERVAL '24 hours')"#,
    )
    .bind(business)
    .bind(uid)
    .fetch_one(db)
    .await?;
    check_limit(count, limit)
}
