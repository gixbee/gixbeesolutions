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
    if matches!(service, "PHOTOGRAPHY" | "CATERING" | "DECORATION") {
        return Ok(());
    }
    Err(AppError::BadRequest(
        "Choose photography, catering or decoration".into(),
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
        if service == "PHOTOGRAPHY" || service == "DECORATION" {
            if service == "PHOTOGRAPHY" {
                validate_photography_metadata(item)?;
            } else {
                validate_decoration_metadata(item)?;
            }
            if !valid_price(item["price"].as_i64()) {
                return Err(invalid());
            }
        } else {
            validate_catering_discounts(item)?;
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

/// Decoration uses a fixed event price (never a client-supplied amount).
/// Discounts are recomputed in integer rupees, matching Flutter's preview.
fn validate_decoration_metadata(item: &Value) -> AppResult<()> {
    let invalid = || AppError::BadRequest("Check decoration items, pricing and add-ons".into());
    if item.get("addon").is_some_and(|v| !v.is_boolean())
        || (item["kind"] == "PACKAGE" && item["addon"] == true)
    {
        return Err(invalid());
    }
    match (item.get("listPrice"), item.get("discountPct")) {
        (None, None) => {}
        (Some(list), Some(pct)) => {
            let list = list.as_i64().ok_or_else(invalid)?;
            let pct = pct.as_i64().ok_or_else(invalid)?;
            let offered = item["price"].as_i64().ok_or_else(invalid)?;
            if !valid_price(Some(list))
                || !(0..=90).contains(&pct)
                || offered != (list * (100 - pct) + 50) / 100
            {
                return Err(invalid());
            }
        }
        _ => return Err(invalid()),
    }
    Ok(())
}

/// The new Flutter photography wizards store structured metadata inside
/// catalogue JSONB. Validate the structure, not just the base package price.
fn validate_photography_metadata(item: &Value) -> AppResult<()> {
    let invalid = || AppError::BadRequest("Check photography package details".into());
    // Customer-facing amount must equal the published list price minus the
    // owner-entered percentage. The event quote selects the saved 'price',
    // never client-supplied discounts or list prices.
    match (item.get("listPrice"), item.get("discountPct")) {
        (None, None) => {}
        (Some(list), Some(pct)) => {
            let list = list.as_i64().ok_or_else(invalid)?;
            let pct = pct.as_i64().ok_or_else(invalid)?;
            let offered = item["price"].as_i64().ok_or_else(invalid)?;
            if !valid_price(Some(list)) || !(0..=90).contains(&pct)
                || offered != (list * (100 - pct) + 50) / 100
            {
                return Err(invalid());
            }
        }
        _ => return Err(invalid()),
    }
    for key in [
        "coverageNotes", "photographerTeam", "videographerTeam",
        "duration", "team", "extrasNotes", "customerRequirements", "packageLevel",
        "equipmentNote", "qualityNote",
    ] {
        if item.get(key).is_some_and(|v| {
            v.as_str().is_none_or(|s| s.len() > 3000)
        }) {
            return Err(invalid());
        }
    }
    for key in ["functions", "ceremonies", "inclusions", "extras"] {
        if let Some(value) = item.get(key) {
            let items = value.as_array().ok_or_else(invalid)?;
            if items.len() > 20 || items.iter().any(|v| {
                v.as_str().is_none_or(|s| s.trim().is_empty() || s.len() > 150)
            }) {
                return Err(invalid());
            }
            let distinct = items.iter().filter_map(Value::as_str)
                .collect::<std::collections::HashSet<_>>();
            if distinct.len() != items.len() {
                return Err(invalid());
            }
        }
    }
    // Details are optional for legacy catalogues. Enforce a bounded shape
    // for structured per-function coverage and per-deliverable quantities.
    for key in ["functionCoverage", "deliverableDetails", "deliveryTimelines"] {
        if let Some(rows) = item.get(key) {
            let rows = rows.as_object().ok_or_else(invalid)?;
            if rows.len() > 30 || rows.iter().any(|(name, entry)| {
                name.trim().is_empty() || name.len() > 150
                    || !entry.is_object()
                    || entry.to_string().len() > 2400
            }) {
                return Err(invalid());
            }
        }
    }
    for key in ["policyRules", "cancelRules", "rescheduleRules"] {
        if let Some(rules) = item.get(key) {
            let rules = rules.as_array().ok_or_else(invalid)?;
            if rules.len() > 10 || rules.iter().any(|row| {
                row["label"].as_str().is_none_or(|s| s.trim().is_empty() || s.len() > 150)
                    || row["deductionPercent"].as_i64()
                        .is_none_or(|p| !(0..=100).contains(&p))
            }) { return Err(invalid()); }
        }
    }
    if let Some(prices) = item.get("extraPrices") {
        let prices = prices.as_object().ok_or_else(invalid)?;
        let selected = item["extras"].as_array().ok_or_else(invalid)?;
        if prices.len() > 20 || prices.iter().any(|(key, amount)| {
            key.trim().is_empty() || key.len() > 150
                || !selected.iter().any(|name| name.as_str() == Some(key.as_str()))
                || amount.as_i64().is_none_or(|v| !(0..=10_000_000).contains(&v))
        }) { return Err(invalid()); }
    }
    if let Some(qty) = item.get("deliverableDetails") {
        for detail in qty.as_object().ok_or_else(invalid)?.values() {
            if detail.get("quantity").is_some_and(|value| {
                value.as_i64().is_none_or(|n| !(1..=100_000).contains(&n))
            }) { return Err(invalid()); }
        }
    }
    if let Some(timing) = item.get("deliveryTimelines") {
        for detail in timing.as_object().ok_or_else(invalid)?.values() {
            if detail.get("days").is_some_and(|value| {
                value.as_i64().is_none_or(|n| !(0..=730).contains(&n))
            }) { return Err(invalid()); }
        }
    }
    if item.get("extraHourPrice").is_some_and(|v| {
        v.as_i64().is_none_or(|p| !(0..=10_000_000).contains(&p))
    }) {
        return Err(invalid());
    }
    if let Some(stages) = item.get("paymentSplit") {
        if item["kind"] != "PACKAGE" {
            return Err(invalid());
        }
        let stages = stages.as_array().ok_or_else(invalid)?;
        if stages.is_empty() || stages.len() > 6 {
            return Err(invalid());
        }
        let mut total = 0_i64;
        for stage in stages {
            let label = stage["label"].as_str().ok_or_else(invalid)?;
            let pct = stage["percent"].as_i64().ok_or_else(invalid)?;
            if label.trim().is_empty() || label.len() > 150 || !(1..=100).contains(&pct) {
                return Err(invalid());
            }
            total += pct;
        }
        if total != 100 {
            return Err(invalid());
        }
    }
    Ok(())
}

/// Optional catering offers must agree with their published per-guest slabs.
/// Prevent clients from sending a fake discount badge without discounted prices.
fn validate_catering_discounts(item: &Value) -> AppResult<()> {
    let invalid = || AppError::BadRequest("Check catering discount and guest pricing".into());
    let pct = item.get("discountPct").map(|v| v.as_i64().ok_or_else(invalid))
        .transpose()?.unwrap_or(0);
    if !(0..=90).contains(&pct) { return Err(invalid()); }
    let Some(base) = item.get("baseTiers") else {
        if pct != 0 { return Err(invalid()); }
        return Ok(());
    };
    let base = base.as_array().ok_or_else(invalid)?;
    let displayed = item["tiers"].as_array().ok_or_else(invalid)?;
    if base.is_empty() || base.len() != displayed.len() || base.len() > 20 {
        return Err(invalid());
    }
    if let Some(mode) = item.get("rateMode") {
        match mode.as_str() {
            Some("flat") => {
                if base.len() != 1 || base[0]["minGuests"].as_i64() != Some(1)
                    || base[0]["maxGuests"].as_i64() != Some(100000)
                {
                    return Err(invalid());
                }
            }
            Some("tiered") => {}
            _ => return Err(invalid()),
        }
    }
    for (raw, shown) in base.iter().zip(displayed.iter()) {
        let min = raw["minGuests"].as_i64().ok_or_else(invalid)?;
        let max = raw["maxGuests"].as_i64().ok_or_else(invalid)?;
        let price = raw["price"].as_i64().ok_or_else(invalid)?;
        if !valid_price(Some(price)) || shown["minGuests"].as_i64() != Some(min)
            || shown["maxGuests"].as_i64() != Some(max) {
            return Err(invalid());
        }
        let after_discount = ((price * (100 - pct) + 50) / 100).max(1);
        if shown["price"].as_i64() != Some(after_discount) {
            return Err(invalid());
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
    let mut decoration_packages = 0;
    let mut decoration_regular_items = 0;
    for id in ids {
        let item = catalogue["items"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|item| {
                id.is_string() && item["id"] == *id && item["active"].as_bool() != Some(false)
            })
            .ok_or_else(|| AppError::Conflict("A selected item is no longer available".into()))?;
        if !seen.insert(id.as_str()) {
            return Err(AppError::BadRequest("Select distinct catalogue entries".into()));
        }
        if service == "DECORATION" {
            if item["kind"] == "PACKAGE" {
                decoration_packages += 1;
            } else if item["addon"] != true {
                decoration_regular_items += 1;
            }
            // One package may be combined only with explicitly marked add-ons.
            if decoration_packages > 1 || (decoration_packages > 0 && decoration_regular_items > 0) {
                return Err(AppError::BadRequest(
                    "Choose one decoration package with add-ons, or standalone services".into(),
                ));
            }
        } else if ids.len() > 1 && item["kind"] != "ITEM" {
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
    if !matches!(service, "PHOTOGRAPHY" | "CATERING" | "DECORATION") {
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

#[cfg(test)]
mod catalogue_metadata_tests {
    use super::*;

    #[test]
    fn decoration_catalogue_supports_packages_and_addons() {
        let catalogue = json!({
            "photos":[],
            "items":[
                {"id":"123e4567-e89b-42d3-a456-426614174000","kind":"PACKAGE",
                 "name":"Wedding stage","price":18000,"listPrice":20000,
                 "discountPct":10,"active":true},
                {"id":"123e4567-e89b-42d3-a456-426614174001","kind":"ITEM",
                 "name":"Extra flower arch","price":2500,"addon":true,"active":true}
            ]
        });
        assert!(validate_service("DECORATION").is_ok());
        assert!(validate_catalogue(&catalogue, "DECORATION").is_ok());
    }

    #[test]
    fn decoration_rejects_fake_prices_and_package_addon_flag() {
        let mut item = json!({"kind":"PACKAGE","price":18000,
            "listPrice":20000,"discountPct":10});
        assert!(validate_decoration_metadata(&item).is_ok());
        item["price"] = json!(18001);
        assert!(validate_decoration_metadata(&item).is_err());
        item["price"] = json!(18000);
        item["addon"] = json!(true);
        assert!(validate_decoration_metadata(&item).is_err());
    }

    #[test]
    fn rejects_malformed_photo_payment_split() {
        let item = json!({
            "kind":"PACKAGE",
            "paymentSplit":[
                {"label":"Advance","percent":40},
                {"label":"Final","percent":40}
            ]
        });
        assert!(validate_photography_metadata(&item).is_err());
    }

    #[test]
    fn accepts_wizard_photo_metadata() {
        let item = json!({
            "kind":"PACKAGE",
            "functions":["Wedding","Reception"],
            "inclusions":["Edited Photos"],
            "paymentSplit":[
                {"label":"Advance","percent":30},
                {"label":"Final","percent":70}
            ]
        });
        assert!(validate_photography_metadata(&item).is_ok());
    }

    #[test]
    fn photo_discount_must_match_customer_price() {
        let mut item = json!({
            "kind":"PACKAGE", "price": 51, "listPrice": 101,
            "discountPct": 50
        });
        assert!(validate_photography_metadata(&item).is_ok());
        item["price"] = json!(50);
        assert!(validate_photography_metadata(&item).is_err());
        item["price"] = json!(51);
        item["discountPct"] = json!(91);
        assert!(validate_photography_metadata(&item).is_err());
        item["discountPct"] = json!(50);
        item["listPrice"] = json!(null);
        assert!(validate_photography_metadata(&item).is_err());
    }

    #[test]
    fn validates_structured_photo_owner_metadata() {
        let item = json!({
            "kind":"PACKAGE",
            "price":90000, "listPrice":100000, "discountPct":10,
            "functionCoverage":{"Wedding":{"duration":"6 hours", "side":"Both"}},
            "deliverableDetails":{"Edited Photos":{"quantity":400,"format":"JPG"}},
            "deliveryTimelines":{"Edited Photos":{"days":15}},
            "policyRules":[{"label":"30+ days","deductionPercent":10}],
            "paymentSplit":[
                {"label":"Booking advance","percent":30},
                {"label":"Event day","percent":40},
                {"label":"Before album printing","percent":20},
                {"label":"Final","percent":10}
            ]
        });
        assert!(validate_photography_metadata(&item).is_ok());
        let mut bad = item.clone();
        bad["deliverableDetails"] = json!([{"quantity":400}]);
        assert!(validate_photography_metadata(&bad).is_err());
    }

    #[test]
    fn rejects_photo_invalid_addons_and_policy_deductions() {
        let mut item = json!({
            "kind":"PACKAGE","price":10000,"listPrice":10000,"discountPct":0,
            "extras":["Drone / Helicam"],
            "extraPrices":{"Drone / Helicam":2000},
            "cancelRules":[{"label":"30 days or more","deductionPercent":10}],
            "rescheduleRules":[{"label":"30 days or more","deductionPercent":0}],
            "deliverableDetails":{"Edited Photos":{"quantity":100}},
            "deliveryTimelines":{"Edited Photos":{"days":15}}
        });
        assert!(validate_photography_metadata(&item).is_ok());
        item["extraPrices"]["Other"] = json!(900);
        assert!(validate_photography_metadata(&item).is_err());
        item["extraPrices"].as_object_mut().unwrap().remove("Other");
        item["cancelRules"][0]["deductionPercent"] = json!(101);
        assert!(validate_photography_metadata(&item).is_err());
        item["cancelRules"][0]["deductionPercent"] = json!(10);
        item["deliverableDetails"]["Edited Photos"]["quantity"] = json!(0);
        assert!(validate_photography_metadata(&item).is_err());
    }

    #[test]
    fn validates_discounted_catering_price() {
        let item = json!({
            "discountPct":10,
            "baseTiers":[{"minGuests":1,"maxGuests":200,"price":200}],
            "tiers":[{"minGuests":1,"maxGuests":200,"price":180}]
        });
        assert!(validate_catering_discounts(&item).is_ok());
    }
    #[test]
    fn catering_rounds_half_up_exactly_like_flutter() {
        let item = json!({
            "kind": "ITEM", "rateMode": "tiered", "discountPct": 50,
            "baseTiers": [{"minGuests":1, "maxGuests":100, "price":101}],
            "tiers": [{"minGuests":1, "maxGuests":100, "price":51}]
        });
        assert!(validate_catering_discounts(&item).is_ok());
        let mut bad = item.clone();
        bad["tiers"][0]["price"] = json!(50);
        assert!(validate_catering_discounts(&bad).is_err());
    }

    #[test]
    fn catering_rejects_fake_flat_rate_and_wrong_offer() {
        let mut item = json!({
            "kind": "PACKAGE", "rateMode": "flat", "discountPct": 10,
            "baseTiers": [{"minGuests":1, "maxGuests":100, "price":500}],
            "tiers": [{"minGuests":1, "maxGuests":100, "price":450}]
        });
        assert!(validate_catering_discounts(&item).is_err());
        item["baseTiers"][0]["maxGuests"] = json!(100000);
        item["tiers"][0]["maxGuests"] = json!(100000);
        assert!(validate_catering_discounts(&item).is_ok());
        item["tiers"][0]["price"] = json!(500);
        assert!(validate_catering_discounts(&item).is_err());
    }

    #[test]
    fn catering_menu_snapshot_updates_when_dish_is_edited() {
        let dish_id = "22222222-2222-4222-8222-222222222222";
        let package_id = "33333333-3333-4333-8333-333333333333";
        let mut catalogue = json!({
            "photos": [],
            "items": [
                {
                    "id": dish_id, "kind": "ITEM",
                    "name": "Welcome Drink", "category": "g01",
                    "diet": "veg", "active": true,
                    "tiers": [{"minGuests":1,"maxGuests":100,"price":100}]
                },
                {
                    "id": package_id, "kind": "PACKAGE",
                    "name": "Wedding Feast", "active": true,
                    "dishIds": [dish_id], "discountPct": 10,
                    "rateMode": "tiered",
                    "baseTiers": [{"minGuests":1,"maxGuests":100,"price":500}],
                    "tiers": [{"minGuests":1,"maxGuests":100,"price":450}]
                }
            ]
        });
        assert!(validate_catalogue(&catalogue, "CATERING").is_ok());
        populate_menus(&mut catalogue).unwrap();
        assert_eq!(catalogue["items"][1]["menuItems"], json!(["Welcome Drink"]));
        catalogue["items"][0]["name"] = json!("Mango Welcome Drink");
        populate_menus(&mut catalogue).unwrap();
        assert_eq!(catalogue["items"][1]["menuItems"], json!(["Mango Welcome Drink"]));
    }

}
