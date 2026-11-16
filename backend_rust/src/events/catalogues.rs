use super::*;
use sqlx::PgConnection;

pub(super) fn routes() -> Router<AppState> {
    Router::new().route("/catalogues", get(discover)).route(
        "/catalogues/{business_id}/{service}",
        get(get_catalogue).put(save_catalogue),
    )
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Browse {
    service_type: String,
    city_id: Uuid,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Save {
    revision: i32,
    catalogue: Value,
}

fn validate_service(service: &str) -> AppResult<()> {
    if matches!(service, "PHOTOGRAPHY" | "CATERING") {
        return Ok(());
    }
    Err(AppError::BadRequest(
        "Choose photography or catering".into(),
    ))
}

async fn discover(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(query): Query<Browse>,
) -> AppResult<Json<Vec<Value>>> {
    validate_service(&query.service_type)?;
    let vendors = sqlx::query_scalar(
        r#"SELECT jsonb_build_object('businessId', b.id, 'name', b.name,
               'location', b.location, 'catalogue', c.catalogue)
           FROM event_service_catalogues c JOIN businesses b ON b.id=c."businessId"
           WHERE c."serviceType"=$1 AND (b."cityId"=$2::uuid OR c.catalogue->'serviceCityIds' ? ($2::uuid)::text)
             AND b.type='SERVICE'
             AND b.status='VERIFIED'
             AND (b."serviceType"::text=$1 OR b."eventServices" ? $1)
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(c.catalogue->'items') item
                         WHERE item->'active' IS DISTINCT FROM 'false'::jsonb)
           ORDER BY b.name,b.id LIMIT 100"#,
    )
    .bind(query.service_type)
    .bind(query.city_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(vendors))
}

async fn get_catalogue(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business, service)): Path<(Uuid, String)>,
) -> AppResult<Json<Value>> {
    validate_service(&service)?;
    let value = sqlx::query_scalar(
        r#"SELECT jsonb_build_object('revision', COALESCE(c.revision,0),
                 'catalogue', COALESCE(c.catalogue, '{"items":[],"photos":[]}'::jsonb))
           FROM businesses b LEFT JOIN event_service_catalogues c
             ON c."businessId"=b.id AND c."serviceType"=$3
           WHERE b.id=$1 AND b."ownerId"=$2 AND b.type='SERVICE'
             AND (b."serviceType"::text=$3 OR b."eventServices" ? $3)"#,
    )
    .bind(business)
    .bind(Uuid::parse_str(&user.user_id)?)
    .bind(service)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("Business service not found".into()))?;
    Ok(Json(value))
}

async fn save_catalogue(
    State(state): State<AppState>,
    user: AuthUser,
    Path((business, service)): Path<(Uuid, String)>,
    Json(mut input): Json<Save>,
) -> AppResult<Json<Value>> {
    validate_service(&service)?;
    validate_catalogue(&input.catalogue, &service)?;
    if service == "CATERING" {
        populate_menus(&mut input.catalogue)?;
    }
    let mut tx = state.db.begin().await?;
    let owned: Option<Uuid> = sqlx::query_scalar(
        r#"SELECT id FROM businesses WHERE id=$1 AND "ownerId"=$2 AND type='SERVICE'
           AND ("serviceType"::text=$3 OR "eventServices" ? $3) FOR UPDATE"#,
    )
    .bind(business)
    .bind(Uuid::parse_str(&user.user_id)?)
    .bind(&service)
    .fetch_optional(&mut *tx)
    .await?;
    if owned.is_none() {
        return Err(AppError::NotFound("Business service not found".into()));
    }
    let revision: i32 = sqlx::query_scalar(
        r#"SELECT revision FROM event_service_catalogues WHERE "businessId"=$1 AND "serviceType"=$2"#,
    )
    .bind(business)
    .bind(&service)
    .fetch_optional(&mut *tx)
    .await?
    .unwrap_or(0);
    if revision != input.revision {
        return Err(AppError::Conflict(
            "Catalogue changed. Reload before saving again.".into(),
        ));
    }
    let service_cities: Vec<Uuid> = input.catalogue["serviceCityIds"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|city| {
            serde_json::from_value(city.clone())
                .map_err(|_| AppError::BadRequest("Choose valid service areas".into()))
        })
        .collect::<AppResult<_>>()?;
    let valid_cities: i64 =
        sqlx::query_scalar(r#"SELECT count(*) FROM cities WHERE id=ANY($1) AND "isActive""#)
            .bind(&service_cities)
            .fetch_one(&mut *tx)
            .await?;
    if valid_cities != service_cities.len() as i64 {
        return Err(AppError::BadRequest(
            "Choose active, distinct service areas".into(),
        ));
    }
    let revision: i32 = sqlx::query_scalar(
        r#"INSERT INTO event_service_catalogues ("businessId","serviceType",catalogue)
           VALUES ($1,$2,$3)
           ON CONFLICT ("businessId","serviceType") DO UPDATE
           SET catalogue=EXCLUDED.catalogue, revision=event_service_catalogues.revision+1
           RETURNING revision"#,
    )
    .bind(business)
    .bind(service)
    .bind(&input.catalogue)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(
        json!({"revision": revision, "catalogue": input.catalogue}),
    ))
}

fn validate_catalogue(catalogue: &Value, service: &str) -> AppResult<()> {
    const MAX_TEXT: usize = 3000;
    let invalid = || AppError::BadRequest("Check the catalogue fields and pricing".into());
    let items = catalogue["items"].as_array().ok_or_else(invalid)?;
    let photos = catalogue["photos"].as_array().ok_or_else(invalid)?;
    let mut ids = std::collections::HashSet::new();
    if items.len() > 150
        || photos.len() > 24
        || catalogue.to_string().len() > 300_000
        || catalogue
            .get("serviceCityIds")
            .is_some_and(|areas| areas.as_array().is_none_or(|a| a.len() > 30))
        || catalogue
            .get("maxBookingsPerDay")
            .is_some_and(|v| v.as_i64().is_none_or(|n| !(1..=50).contains(&n)))
        || catalogue
            .get("maxAdvanceDays")
            .is_some_and(|v| v.as_i64().is_none_or(|n| !(1..=730).contains(&n)))
        || catalogue.get("minNoticeDays").is_some_and(|v| {
            v.as_i64().is_none_or(|n| {
                n < 0 || n > 365 || n > catalogue["maxAdvanceDays"].as_i64().unwrap_or(730)
            })
        })
        || catalogue["about"].as_str().unwrap_or("").len() > MAX_TEXT
        || photos.iter().any(|photo| {
            !photo.as_str().is_some_and(|url| {
                url.len() <= 600 && (url.starts_with("/uploads/") || url.starts_with("https://"))
            })
        })
    {
        return Err(invalid());
    }
    for item in items {
        let id = item["id"]
            .as_str()
            .and_then(|id| Uuid::parse_str(id).ok())
            .ok_or_else(invalid)?;
        if !ids.insert(id)
            || !item["name"]
                .as_str()
                .is_some_and(|name| !name.trim().is_empty() && name.len() <= 150)
            || !matches!(item["kind"].as_str(), Some("PACKAGE" | "ITEM"))
            || item.get("active").is_some_and(|value| !value.is_boolean())
            || [
                "description",
                "includes",
                "policy",
                "category",
                "delivery",
                "paymentStages",
                "diet",
                "serveStyle",
            ]
            .iter()
            .any(|key| item[*key].as_str().unwrap_or("").len() > MAX_TEXT)
        {
            return Err(invalid());
        }
        if service == "PHOTOGRAPHY" {
            if !valid_price(item["price"].as_i64()) {
                return Err(invalid());
            }
        } else {
            let tiers = item["tiers"].as_array().ok_or_else(invalid)?;
            let mut previous_end = 0;
            if tiers.is_empty() || tiers.len() > 20 {
                return Err(invalid());
            }
            for tier in tiers {
                let min = tier["minGuests"].as_i64().ok_or_else(invalid)?;
                let max = tier["maxGuests"].as_i64().ok_or_else(invalid)?;
                if min <= previous_end
                    || max < min
                    || max > 100000
                    || !valid_price(tier["price"].as_i64())
                {
                    return Err(invalid());
                }
                previous_end = max;
            }
        }
    }
    Ok(())
}

fn populate_menus(catalogue: &mut Value) -> AppResult<()> {
    let items = catalogue["items"].as_array_mut().expect("validated items");
    let dishes: std::collections::HashMap<String, Value> = items
        .iter()
        .filter(|item| item["kind"] == "ITEM")
        .filter_map(|item| Some((item["id"].as_str()?.to_owned(), item["name"].clone())))
        .collect();
    for package in items.iter_mut().filter(|item| item["kind"] == "PACKAGE") {
        let Some(ids) = package.get("dishIds") else {
            continue;
        };
        let mut selected = std::collections::HashSet::new();
        let menu = ids
            .as_array()
            .ok_or_else(|| AppError::BadRequest("Choose dishes from the menu".into()))?
            .iter()
            .map(|value| {
                value
                    .as_str()
                    .filter(|id| selected.insert(*id))
                    .and_then(|id| dishes.get(id))
                    .cloned()
                    .ok_or_else(|| {
                        AppError::BadRequest("Choose distinct dishes from the menu".into())
                    })
            })
            .collect::<AppResult<Vec<_>>>()?;
        package["menuItems"] = json!(menu);
    }
    Ok(())
}

fn valid_price(price: Option<i64>) -> bool {
    price.is_some_and(|price| (1..=10_000_000).contains(&price))
}

pub(super) async fn selection(
    tx: &mut PgConnection,
    business: Uuid,
    service: &str,
    guests: i32,
    start: DateTime<Utc>,
    requested: &Value,
) -> AppResult<Value> {
    validate_service(service)?;
    let ids = requested["itemIds"]
        .as_array()
        .ok_or_else(|| AppError::BadRequest("Select a package or service".into()))?;
    if ids.is_empty() || ids.len() > 20 || (service == "PHOTOGRAPHY" && ids.len() != 1) {
        return Err(AppError::BadRequest(
            "Select a package or up to 20 dishes".into(),
        ));
    }
    let catalogue: Value = sqlx::query_scalar(
        r#"SELECT catalogue FROM event_service_catalogues WHERE "businessId"=$1 AND "serviceType"=$2"#,
    )
    .bind(business)
    .bind(service)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::NotFound("This catalogue is no longer available".into()))?;
    let today = india_day(Utc::now());
    let days = (india_day(start) - today).num_days();
    if days < catalogue["minNoticeDays"].as_i64().unwrap_or(0)
        || days > catalogue["maxAdvanceDays"].as_i64().unwrap_or(730)
    {
        return Err(AppError::Conflict(
            "Choose a date within the provider's booking window".into(),
        ));
    }
    let mut seen = std::collections::HashSet::new();
    let mut lines = Vec::new();
    let mut estimate = 0;
    for id in ids {
        let item = catalogue["items"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|item| {
                id.is_string() && item["id"] == *id && item["active"].as_bool() != Some(false)
            })
            .ok_or_else(|| AppError::Conflict("A selected item is no longer available".into()))?;
        if !seen.insert(id.as_str()) || (ids.len() > 1 && item["kind"] != "ITEM") {
            return Err(AppError::BadRequest(
                "Select one package or distinct dishes".into(),
            ));
        }
        let price = if service == "CATERING" {
            item["tiers"]
                .as_array()
                .into_iter()
                .flatten()
                .find(|tier| {
                    tier["minGuests"]
                        .as_i64()
                        .is_some_and(|min| min <= i64::from(guests))
                        && tier["maxGuests"]
                            .as_i64()
                            .is_some_and(|max| max >= i64::from(guests))
                })
                .and_then(|tier| tier["price"].as_i64())
        } else {
            item["price"].as_i64()
        }
        .ok_or_else(|| {
            AppError::Conflict("A selected item has no price for this guest count".into())
        })?;
        estimate += if service == "CATERING" {
            price * i64::from(guests)
        } else {
            price
        };
        lines.push(json!({"item": item, "unitPrice": price}));
    }
    if estimate > 999_999_999 {
        return Err(AppError::BadRequest(
            "The selected estimate is above the supported quote amount".into(),
        ));
    }
    Ok(json!({"kind": service, "items": lines, "estimate": estimate}))
}

fn india_day(instant: DateTime<Utc>) -> chrono::NaiveDate {
    instant
        .with_timezone(&chrono::FixedOffset::east_opt(19800).unwrap())
        .date_naive()
}

pub(super) async fn check_daily_limit(
    conn: &mut PgConnection,
    business: Uuid,
    service: &str,
    plan: Uuid,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> AppResult<()> {
    if !matches!(service, "PHOTOGRAPHY" | "CATERING") {
        return Ok(());
    }
    let limit: Option<i64> = sqlx::query_scalar::<_, Option<i64>>(
        r#"SELECT (catalogue->>'maxBookingsPerDay')::bigint FROM event_service_catalogues
           WHERE "businessId"=$1 AND "serviceType"=$2"#,
    )
    .bind(business)
    .bind(service)
    .fetch_optional(&mut *conn)
    .await?
    .flatten();
    if let Some(limit) = limit {
        let full: bool = sqlx::query_scalar(
            r#"SELECT EXISTS (
                  SELECT 1 FROM generate_series($4::date::timestamp,$5::date::timestamp,interval '1 day') day
                  JOIN (
                    SELECT p."startTime" AS starts, p."endTime" AS ends
                    FROM event_quotes q JOIN event_plans p ON p.id=q."planId"
                    WHERE q."businessId"=$1 AND q."serviceType"=$2 AND q."planId"<>$3
                      AND q.status IN ('CONFIRMED','CANCEL_REQUESTED','COMPLETED')
                    UNION ALL
                    SELECT "startAt","endAt" FROM event_vendor_calendar
                    WHERE "businessId"=$1 AND "cancelledAt" IS NULL
                  ) occupied ON (occupied.starts AT TIME ZONE 'Asia/Kolkata')<day+interval '1 day'
                    AND (occupied.ends AT TIME ZONE 'Asia/Kolkata')>day
                  GROUP BY day HAVING count(*) >= $6
                )"#,
        )
        .bind(business).bind(service).bind(plan).bind(india_day(start))
        .bind(india_day(end - chrono::Duration::milliseconds(1))).bind(limit)
        .fetch_one(&mut *conn).await?;
        if full {
            return Err(AppError::Conflict(
                "The provider is fully booked on an event day".into(),
            ));
        }
    }
    Ok(())
}
