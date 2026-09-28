use axum::{
    extract::{Path, Query, State},
    routing::{get, patch, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::common::pg::BUSINESS_COLS;
use crate::error::{AppError, AppResult};
use crate::middleware::auth::AuthUser;
use crate::state::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/", post(create))
        .route("/my", get(list))
        .route("/admin/all", get(admin_list))
        .route("/admin/{id}/status", patch(admin_status))
        .route("/{id}", get(get_one).patch(update).delete(remove))
        .route("/{id}/operators", post(add_operator))
        .route(
            "/{id}/calendar/offline",
            post(add_offline_day).delete(remove_offline_day),
        )
}

async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<Value>>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let rows = sqlx::query(&format!(
        r#"SELECT {BUSINESS_COLS} FROM businesses WHERE "ownerId" = $1 ORDER BY "createdAt" DESC"#
    ))
    .bind(uid)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.iter().map(business_json).collect()))
}

async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let uid = Uuid::parse_str(&user.user_id)?;
    let id = Uuid::new_v4();
    let name = body
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim();
    let biz_type = body
        .get("type")
        .and_then(|v| v.as_str())
        .unwrap_or("SERVICE");
    let location = body
        .get("address")
        .or_else(|| body.get("location"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    if name.is_empty() || name.len() > 200 || location.is_empty() || location.len() > 1000 {
        return Err(AppError::BadRequest(
            "A business name and address are required".into(),
        ));
    }
    if !["SERVICE", "HIRING", "RENTAL"].contains(&biz_type) {
        return Err(AppError::BadRequest("Unsupported business type".into()));
    }
    let service_type = body.get("serviceType").and_then(Value::as_str);
    if service_type.is_some_and(|s| !["HALL", "CATERING", "DECORATION", "PHOTOGRAPHY"].contains(&s))
    {
        return Err(AppError::BadRequest("Unsupported service type".into()));
    }
    let city_id = resolve_city_id(
        &state.db,
        body.get("cityId")
            .and_then(Value::as_str)
            .map(Uuid::parse_str)
            .transpose()?,
    )
    .await?;
    let event_services = event_services(body.get("eventServices"))?;
    let phone = phone(body.get("phone"))?;
    let hiring_profile = hiring_profile(body.get("hiringProfile"), biz_type)?;
    sqlx::query(
        r#"INSERT INTO businesses (id, "ownerId", name, type, location, status,
           "serviceType", "cityId", description, "documentUrl",phone,"eventServices","hiringProfile")
           VALUES ($1, $2, $3, $4::businesses_type_enum, $5, 'PENDING',
           $6::businesses_servicetype_enum, $7, $8, $9,$10,$11,$12)"#,
    )
    .bind(id)
    .bind(uid)
    .bind(name)
    .bind(biz_type)
    .bind(location)
    .bind(if biz_type == "SERVICE" {
        service_type
    } else {
        None
    })
    .bind(city_id)
    .bind(body.get("description").and_then(Value::as_str))
    .bind(body.get("documentUrl").and_then(Value::as_str))
    .bind(phone)
    .bind(json!(if biz_type=="SERVICE" {event_services} else {vec![]}))
    .bind(hiring_profile)
    .execute(&state.db)
    .await?;
    get_one(State(state), user, Path(id.to_string())).await
}

/// Accept a live city, or drop a stale cached UUID so POST /businesses does
/// not 400 on `businesses_cityId_fkey` after cities are re-seeded.
async fn resolve_city_id(
    db: &sqlx::PgPool,
    city_id: Option<Uuid>,
) -> AppResult<Option<Uuid>> {
    let Some(id) = city_id else {
        return Ok(None);
    };
    let active: bool = sqlx::query_scalar(
        r#"SELECT EXISTS(SELECT 1 FROM cities WHERE id = $1 AND "isActive" = true)"#,
    )
    .bind(id)
    .fetch_one(db)
    .await?;
    if active {
        Ok(Some(id))
    } else {
        tracing::warn!(%id, "dropping unknown or inactive cityId on POST /businesses");
        Ok(None)
    }
}

async fn get_one(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let row = sqlx::query(&format!(
        r#"SELECT {BUSINESS_COLS} FROM businesses WHERE id = $1"#
    ))
    .bind(bid)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    let mut result=business_json(&row);
    let owns=row.get::<Uuid,_>("ownerId").to_string()==user.user_id;
    let admin=crate::middleware::auth::require_admin_page(&user,"businesses").is_ok();
    if !owns && !admin {
        if row.get::<String,_>("status")!="VERIFIED" {return Err(AppError::NotFound("Business not found".into()));}
        result.as_object_mut().unwrap().remove("documentUrl");
        result.as_object_mut().unwrap().remove("operatorIds");
        result.as_object_mut().unwrap().remove("hiringProfile");
    }
    Ok(Json(result))
}

async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let uid = Uuid::parse_str(&user.user_id)?;
    let mut tx = state.db.begin().await?;
    let owned = sqlx::query(r#"SELECT name, type::text AS type, status::text AS status FROM businesses WHERE id = $1 AND "ownerId" = $2 FOR UPDATE"#)
        .bind(bid).bind(uid).fetch_optional(&mut *tx).await?
        .ok_or_else(|| AppError::NotFound("Business not found on your account".into()))?;
    if let Some(name) = body.get("name").and_then(|v| v.as_str()) {
        let name = name.trim();
        if name.is_empty() || name.len() > 200 {
            return Err(AppError::BadRequest(
                "A valid business name is required".into(),
            ));
        }
        if owned.get::<String, _>("status") == "VERIFIED" && name != owned.get::<String, _>("name")
        {
            return Err(AppError::BadRequest(
                "Contact support to change a verified business name".into(),
            ));
        }
        sqlx::query(r#"UPDATE businesses SET name = $1 WHERE id = $2"#)
            .bind(name)
            .bind(bid)
            .execute(&mut *tx)
            .await?;
    }
    for (field, column) in [("address", "location"), ("description", "description")] {
        if let Some(value) = body.get(field).and_then(Value::as_str) {
            if field == "address" && value.trim().is_empty() {
                return Err(AppError::BadRequest("Address cannot be empty".into()));
            }
            sqlx::query(&format!(
                "UPDATE businesses SET {column} = $1 WHERE id = $2"
            ))
            .bind(value.trim())
            .bind(bid)
            .execute(&mut *tx)
            .await?;
        }
    }
    if body.get("phone").is_some() {
        sqlx::query("UPDATE businesses SET phone=$1 WHERE id=$2").bind(phone(body.get("phone"))?).bind(bid).execute(&mut *tx).await?;
    }
    if body.get("eventServices").is_some() {
        let services=event_services(body.get("eventServices"))?;
        let primary=services.iter().find(|s|["HALL","CATERING","DECORATION","PHOTOGRAPHY"].contains(&s.as_str()));
        sqlx::query(r#"UPDATE businesses SET "eventServices"=$1,"serviceType"=$3::businesses_servicetype_enum WHERE id=$2 AND type='SERVICE'"#)
            .bind(json!(services)).bind(bid).bind(primary.map(String::as_str)).execute(&mut *tx).await?;
    }
    if let Some(city)=body.get("cityId").and_then(Value::as_str) {
        let city=Uuid::parse_str(city)?;
        let active:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM cities WHERE id=$1 AND "isActive"=true)"#)
            .bind(city).fetch_one(&mut *tx).await?;
        if !active {return Err(AppError::BadRequest("Select an active serviceable city".into()));}
        sqlx::query(r#"UPDATE businesses SET "cityId"=$1 WHERE id=$2"#).bind(city).bind(bid).execute(&mut *tx).await?;
    }
    let current_status = owned.get::<String, _>("status");
    let biz_type = owned.get::<String, _>("type");
    let mut resubmit = false;
    if body.get("documentUrl").is_some() {
        if current_status == "VERIFIED" {
            return Err(AppError::BadRequest(
                "Contact support to change documents on a verified business".into(),
            ));
        }
        sqlx::query(r#"UPDATE businesses SET "documentUrl"=$1 WHERE id=$2"#)
            .bind(body.get("documentUrl").and_then(Value::as_str))
            .bind(bid)
            .execute(&mut *tx)
            .await?;
        resubmit = true;
    }
    if body.get("hiringProfile").is_some() {
        if biz_type != "HIRING" {
            return Err(AppError::BadRequest(
                "Hiring profile is only for hiring businesses".into(),
            ));
        }
        if current_status == "VERIFIED" {
            return Err(AppError::BadRequest(
                "Contact support to change a verified hiring profile".into(),
            ));
        }
        let cleaned = hiring_profile(body.get("hiringProfile"), "HIRING")?;
        if cleaned
            .as_object()
            .map(|o| o.is_empty())
            .unwrap_or(true)
        {
            return Err(AppError::BadRequest(
                "Hiring verification details are required".into(),
            ));
        }
        sqlx::query(r#"UPDATE businesses SET "hiringProfile"=$1 WHERE id=$2"#)
            .bind(cleaned)
            .bind(bid)
            .execute(&mut *tx)
            .await?;
        resubmit = true;
    }
    if resubmit && current_status == "NEEDS_CHANGES" {
        sqlx::query(
            r#"UPDATE businesses SET status='PENDING'::businesses_status_enum,
               "hiringProfile" = COALESCE("hiringProfile", '{}'::jsonb) - 'reviewNote'
               WHERE id=$1"#,
        )
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query(r#"UPDATE businesses SET "updatedAt" = NOW() WHERE id = $1"#)
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    get_one(State(state), user, Path(id)).await
}

async fn remove(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let result = sqlx::query(
        r#"DELETE FROM businesses WHERE id = $1 AND "ownerId" = $2 AND status::text != 'VERIFIED'"#,
    )
    .bind(bid)
    .bind(Uuid::parse_str(&user.user_id)?)
    .execute(&state.db)
    .await?;
    if result.rows_affected() == 0 {
        return Err(AppError::BadRequest("Only your unverified draft can be deleted; contact support to close a verified business".into()));
    }
    Ok(Json(json!({ "message": "Deleted" })))
}

async fn add_operator(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let bid = Uuid::parse_str(&id)?;
    let operator_id = body
        .get("userId")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("userId required".into()))?;
    let _uid = Uuid::parse_str(operator_id)?;
    let mut tx = state.db.begin().await?;
    let row = sqlx::query_scalar::<_, Option<String>>(
        r#"SELECT "operatorIds" FROM businesses WHERE id = $1 AND "ownerId" = $2 FOR UPDATE"#,
    )
    .bind(bid)
    .bind(Uuid::parse_str(&user.user_id)?)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)")
        .bind(_uid)
        .fetch_one(&mut *tx)
        .await?;
    if !exists {
        return Err(AppError::BadRequest("Operator account not found".into()));
    }
    let mut ops: Vec<String> = row
        .unwrap_or_default()
        .split(',')
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect();
    if !ops.iter().any(|o| o == operator_id) {
        ops.push(operator_id.to_string());
        sqlx::query(r#"UPDATE businesses SET "operatorIds" = $1 WHERE id = $2"#)
            .bind(ops.join(","))
            .bind(bid)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    get_one(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct AdminQuery {
    status: Option<String>,
}

async fn admin_list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AdminQuery>,
) -> AppResult<Json<Vec<Value>>> {
    crate::middleware::auth::require_admin_page(&user, "businesses")?;
    if q.status
        .as_deref()
        .is_some_and(|s| !["PENDING", "VERIFIED", "REJECTED", "NEEDS_CHANGES"].contains(&s))
    {
        return Err(AppError::BadRequest("Invalid moderation status".into()));
    }
    let rows=sqlx::query(&format!(r#"SELECT {BUSINESS_COLS},
        (SELECT jsonb_build_object('id',u.id,'name',u.name,'phoneNumber',u."phoneNumber") FROM users u WHERE u.id=businesses."ownerId") AS owner
        FROM businesses WHERE ($1::text IS NULL OR status::text=$1) ORDER BY "createdAt" DESC LIMIT 500"#))
        .bind(q.status).fetch_all(&state.db).await?;
    Ok(Json(
        rows.iter()
            .map(|row| {
                let mut value = business_json(row);
                value["owner"] = row.get::<Value, _>("owner");
                value
            })
            .collect(),
    ))
}

async fn admin_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    crate::middleware::auth::require_admin_page(&user, "businesses")?;
    let status = body.get("status").and_then(Value::as_str).unwrap_or("");
    if !["PENDING", "VERIFIED", "REJECTED", "NEEDS_CHANGES"].contains(&status) {
        return Err(AppError::BadRequest("Invalid moderation status".into()));
    }
    let review_note = body
        .get("reviewNote")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    if status == "NEEDS_CHANGES" && review_note.is_empty() {
        return Err(AppError::BadRequest(
            "Describe the changes needed".into(),
        ));
    }
    let bid = Uuid::parse_str(&id)?;
    let mut tx = state.db.begin().await?;
    let row = sqlx::query(
        r#"SELECT "ownerId",status::text AS status FROM businesses WHERE id=$1 FOR UPDATE"#,
    )
    .bind(bid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("Business not found".into()))?;
    if row.get::<String, _>("status") != status {
        sqlx::query(r#"UPDATE businesses SET status=$1::businesses_status_enum,"updatedAt"=NOW() WHERE id=$2"#)
            .bind(status).bind(bid).execute(&mut *tx).await?;
        let notify_body = match status {
            "VERIFIED" => "Your business is now verified. You can start posting jobs.",
            "NEEDS_CHANGES" => "Your hiring business needs changes.",
            "REJECTED" => "Your business was not verified.",
            _ => "Your business is under review.",
        };
        crate::outbox::notify(
            &mut tx,
            bid,
            row.get("ownerId"),
            "Business verification update",
            notify_body,
            json!({"type":"business_status","businessId":bid,"status":status}),
        )
        .await?;
    }
    if status == "NEEDS_CHANGES" {
        sqlx::query(
            r#"UPDATE businesses SET "hiringProfile" = COALESCE("hiringProfile", '{}'::jsonb) || jsonb_build_object('reviewNote', $1::text) WHERE id=$2"#,
        )
        .bind(&review_note)
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    } else if status == "VERIFIED" || status == "PENDING" {
        sqlx::query(
            r#"UPDATE businesses SET "hiringProfile" = COALESCE("hiringProfile", '{}'::jsonb) - 'reviewNote' WHERE id=$1"#,
        )
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    get_one(State(state), user, Path(id)).await
}

async fn add_offline_day(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(body): Json<Value>,
) -> AppResult<Json<Value>> {
    let date = body.get("date").and_then(Value::as_str).unwrap_or("");
    change_offline_day(&state, &user, &id, date, true).await?;
    get_one(State(state), user, Path(id)).await
}

#[derive(Deserialize)]
struct OfflineDayQuery {
    date: String,
}

async fn remove_offline_day(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Query(query): Query<OfflineDayQuery>,
) -> AppResult<Json<Value>> {
    change_offline_day(&state, &user, &id, &query.date, false).await?;
    get_one(State(state), user, Path(id)).await
}

async fn change_offline_day(
    state: &AppState,
    user: &AuthUser,
    id: &str,
    date: &str,
    add: bool,
) -> AppResult<()> {
    let date_key = date
        .get(..10)
        .ok_or_else(|| AppError::BadRequest("A valid date is required".into()))?;
    chrono::NaiveDate::parse_from_str(date_key, "%Y-%m-%d")
        .map_err(|_| AppError::BadRequest("A valid date is required".into()))?;
    let bid = Uuid::parse_str(id)?;
    let mut tx = state.db.begin().await?;
    let days = sqlx::query_scalar::<_, Option<Value>>(
        r#"SELECT "offlineDays"::jsonb FROM businesses WHERE id = $1 AND "ownerId" = $2 FOR UPDATE"#)
        .bind(bid).bind(Uuid::parse_str(&user.user_id)?).fetch_optional(&mut *tx).await?
        .ok_or_else(|| AppError::NotFound("Business not found on your account".into()))?;
    let mut days = days.and_then(|v| v.as_array().cloned()).unwrap_or_default();
    days.retain(|v| v.as_str().and_then(|s| s.get(..10)) != Some(date_key));
    if add {
        let booked:bool=sqlx::query_scalar(r#"SELECT EXISTS(SELECT 1 FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
            WHERE q."businessId"=$1 AND q.status IN ('CONFIRMED','CANCEL_REQUESTED')
            AND (p."startTime" AT TIME ZONE 'Asia/Kolkata')::date <= $2::date
            AND ((p."endTime" - INTERVAL '1 millisecond') AT TIME ZONE 'Asia/Kolkata')::date >= $2::date)"#)
            .bind(bid).bind(chrono::NaiveDate::parse_from_str(date_key,"%Y-%m-%d").unwrap()).fetch_one(&mut *tx).await?;
        if booked {return Err(AppError::Conflict("This date has a confirmed event. Resolve the booking before marking it unavailable".into()));}
        days.push(json!(format!("{date_key}T00:00:00.000")));
    }
    sqlx::query(r#"UPDATE businesses SET "offlineDays" = $1, "updatedAt" = NOW() WHERE id = $2"#)
        .bind(serde_json::to_string(&days).map_err(|e| AppError::Internal(e.to_string()))?)
        .bind(bid)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

fn business_json(row: &sqlx::postgres::PgRow) -> Value {
    json!({
        "id": row.get::<Uuid, _>("id").to_string(),
        "ownerId": row.get::<Uuid, _>("ownerId").to_string(),
        "name": row.get::<String, _>("name"),
        "type": row.get::<String, _>("type"),
        "serviceType": row.get::<Option<String>, _>("serviceType"),
        "location": row.get::<String, _>("location"),
        "cityId": row.try_get::<Option<Uuid>, _>("cityId").ok().flatten().map(|u| u.to_string()),
        "description": row.get::<Option<String>, _>("description"),
        "phone": row.get::<Option<String>,_>("phone"),
        "eventServices": row.get::<Value,_>("eventServices"),
        "documentUrl": row.get::<Option<String>, _>("documentUrl"),
        "status": row.get::<String, _>("status"),
        "operatorIds": row.try_get::<Option<String>, _>("operatorIds").ok().flatten().unwrap_or_default().split(',').filter(|s| !s.is_empty()).collect::<Vec<_>>(),
        "offlineDays": row.try_get::<Option<String>, _>("offlineDays").ok().flatten().and_then(|v| serde_json::from_str::<Value>(&v).ok()).unwrap_or(json!([])),
        "hiringProfile": row.try_get::<Value, _>("hiringProfile").ok().unwrap_or(json!({})),
        "createdAt": crate::common::pg::date_json(row,"createdAt"),
        "updatedAt": crate::common::pg::date_json(row,"updatedAt"),
    })
}

fn hiring_profile(value: Option<&Value>, biz_type: &str) -> AppResult<Value> {
    if biz_type != "HIRING" {
        return Ok(json!({}));
    }
    let src = value.cloned().unwrap_or(json!({}));
    if src.as_object().map(|o| o.is_empty()).unwrap_or(true) {
        return Ok(json!({}));
    }
    let kind = src
        .get("employerKind")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    if !["DIRECT", "STAFFING"].contains(&kind) {
        return Err(AppError::BadRequest(
            "Choose Direct Employer or Staffing Agency".into(),
        ));
    }
    let industries: Vec<String> = src
        .get("industries")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|s| !s.is_empty() && s.len() <= 80)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default();
    if industries.is_empty() {
        return Err(AppError::BadRequest("Select at least one industry".into()));
    }
    let role = src
        .get("roleInBusiness")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim();
    if ![
        "Owner",
        "HR",
        "Manager",
        "Recruiter",
        "Authorised Representative",
    ]
    .contains(&role)
    {
        return Err(AppError::BadRequest(
            "Select your role in the business".into(),
        ));
    }
    if src.get("authorised").and_then(Value::as_bool) != Some(true) {
        return Err(AppError::BadRequest(
            "Confirm you are authorised to represent this business".into(),
        ));
    }
    if let Some(reg) = src
        .get("registrationType")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if ![
            "GST Certificate",
            "Udyam Registration",
            "CIN / Company Registration",
            "Business Licence",
            "Other",
        ]
        .contains(&reg)
        {
            return Err(AppError::BadRequest(
                "Unsupported registration type".into(),
            ));
        }
    }
    let mut out = json!({
        "employerKind": kind,
        "industries": industries,
        "roleInBusiness": role,
        "authorised": true,
        "phoneVerified": src.get("phoneVerified").and_then(Value::as_bool).unwrap_or(false),
    });
    if let Some(obj) = out.as_object_mut() {
        for key in [
            "companySize",
            "email",
            "logoUrl",
            "pinLabel",
            "pinSub",
            "registrationType",
            "registrationNumber",
            "otherDocumentType",
            "documentName",
            "workEmail",
        ] {
            if let Some(s) = src.get(key).and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty()) {
                obj.insert(key.to_string(), json!(s));
            }
        }
        if let Some(lat) = src.get("lat").and_then(Value::as_f64) {
            obj.insert("lat".into(), json!(lat));
        }
        if let Some(lng) = src.get("lng").and_then(Value::as_f64) {
            obj.insert("lng".into(), json!(lng));
        }
    }
    Ok(out)
}

fn event_services(value:Option<&Value>)->AppResult<Vec<String>> {
    let mut services:Vec<String>=match value {None=>vec![],Some(v)=>serde_json::from_value(v.clone()).map_err(|_|AppError::BadRequest("Invalid event services".into()))?};
    services.sort();services.dedup();
    if services.iter().any(|s|!crate::events::SERVICES.contains(&s.as_str())) {return Err(AppError::BadRequest("Unsupported event service".into()));}
    Ok(services)
}

fn phone(value: Option<&Value>) -> AppResult<Option<String>> {
    let Some(raw) = value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
    else {
        return Ok(None);
    };
    // Phone keyboards insert `.` `/` `,` `#` `*` and unicode dashes; count
    // digits only so a real 10-digit mobile is not rejected as 400.
    if raw.chars().count() > 40 {
        return Err(AppError::BadRequest(
            "Enter a valid 10-digit business phone number".into(),
        ));
    }
    let mut digits: String = raw.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() == 11 && digits.starts_with('0') {
        digits = digits[1..].to_string();
    }
    if !(10..=15).contains(&digits.len()) {
        return Err(AppError::BadRequest(
            "Enter a valid 10-digit business phone number".into(),
        ));
    }
    Ok(Some(if raw.contains('+') || digits.len() > 10 {
        format!("+{digits}")
    } else {
        digits
    }))
}

#[cfg(test)]
mod phone_tests {
    use super::phone;
    use serde_json::json;

    fn ok(v: &str) -> String {
        phone(Some(&json!(v))).unwrap().unwrap()
    }

    #[test]
    fn accepts_plain_indian_mobile() {
        assert_eq!(ok("9876543210"), "9876543210");
    }

    #[test]
    fn accepts_plus_91_and_spaces() {
        assert_eq!(ok("+91 98765 43210"), "+919876543210");
    }

    #[test]
    fn accepts_keyboard_punctuation() {
        assert_eq!(ok("98765.43210"), "9876543210");
        assert_eq!(ok("tel:+91-9876543210"), "+919876543210");
        assert_eq!(ok("09876543210"), "9876543210");
    }

    #[test]
    fn rejects_too_short() {
        assert!(phone(Some(&json!("98765"))).is_err());
    }
}

#[cfg(test)]
mod hiring_profile_tests {
    use super::hiring_profile;
    use serde_json::json;

    #[test]
    fn non_hiring_drops_profile() {
        assert_eq!(
            hiring_profile(Some(&json!({"employerKind": "DIRECT"})), "RENTAL").unwrap(),
            json!({})
        );
    }

    #[test]
    fn empty_hiring_profile_is_legacy_ok() {
        assert_eq!(hiring_profile(None, "HIRING").unwrap(), json!({}));
    }

    #[test]
    fn hiring_requires_role_and_authorisation() {
        assert!(hiring_profile(
            Some(&json!({
                "employerKind": "DIRECT",
                "industries": ["Retail"]
            })),
            "HIRING"
        )
        .is_err());
    }

    #[test]
    fn hiring_accepts_direct_employer() {
        let v = hiring_profile(
            Some(&json!({
                "employerKind": "DIRECT",
                "industries": ["Retail", "Events"],
                "roleInBusiness": "Owner",
                "authorised": true,
                "lat": 8.52,
                "lng": 76.94
            })),
            "HIRING",
        )
        .unwrap();
        assert_eq!(v["employerKind"], "DIRECT");
        assert_eq!(v["industries"], json!(["Retail", "Events"]));
        assert_eq!(v["lat"], 8.52);
    }

    #[test]
    fn hiring_keeps_optional_registration_and_strips_review_note() {
        let v = hiring_profile(
            Some(&json!({
                "employerKind": "DIRECT",
                "industries": ["Retail"],
                "roleInBusiness": "HR",
                "authorised": true,
                "registrationType": "Other",
                "otherDocumentType": "Shop licence",
                "documentName": "licence.pdf",
                "reviewNote": "client should not set this"
            })),
            "HIRING",
        )
        .unwrap();
        assert_eq!(v["otherDocumentType"], "Shop licence");
        assert_eq!(v["documentName"], "licence.pdf");
        assert!(v.get("reviewNote").is_none());
    }
}
