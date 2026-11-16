use super::*;
use chrono::{FixedOffset, NaiveDate, NaiveTime, TimeZone};
use sqlx::PgConnection;

#[derive(Deserialize)]
pub(super) struct DayQuery {
    day: NaiveDate,
}

pub(super) async fn detail(
    State(state): State<AppState>,
    _user: AuthUser,
    Path(hall): Path<Uuid>,
    Query(query): Query<DayQuery>,
) -> AppResult<Json<Value>> {
    let mut conn = state.db.acquire().await?;
    let (mut details, package) = listed_hall(&mut conn, hall).await?;
    let business: Uuid = serde_json::from_value(details["businessId"].clone())
        .map_err(|_| AppError::NotFound("Hall not found".into()))?;
    let mut slots = Vec::new();
    for offer in package["slotOffers"].as_array().into_iter().flatten() {
        if let Some(interval) = slot_interval(offer, query.day) {
            let available = match check_slot(&mut conn, business, hall, &package, interval).await {
                Ok(()) => true,
                Err(AppError::Conflict(_) | AppError::BadRequest(_)) => false,
                Err(error) => return Err(error),
            };
            let mut display = offer.clone();
            display["offerNoAc"] = json!(offer["offerNoAc"].as_bool().unwrap_or(true));
            // Preserve owner list prices alongside the discounted customer
            // prices; do not apply the percentage discount twice in Flutter.
            display["listPriceNoAc"] = offer["priceNoAc"].clone();
            display["listPriceAc"] = offer["priceAc"].clone();
            display["priceNoAc"] = json!(rent(offer, false));
            display["priceAc"] = json!(rent(offer, true));
            slots.push(json!({"offer": display, "start": interval.start, "end": interval.end, "available": available}));
        }
    }
    details["package"] = package;
    details["slots"] = json!(slots);
    details["photos"] = json!(sqlx::query_scalar::<_, String>(
        r#"SELECT url FROM business_hall_media WHERE "hallId"=$1 ORDER BY "createdAt" DESC LIMIT 24"#,
    )
    .bind(hall)
    .fetch_all(&mut *conn)
    .await?);
    Ok(Json(details))
}

async fn listed_hall(conn: &mut PgConnection, hall: Uuid) -> AppResult<(Value, Value)> {
    let row = sqlx::query(
        r#"SELECT jsonb_build_object('hallId',h.id,'hallName',h.name,'spaceType',h."spaceType",
               'coverImageUrl',h."coverImageUrl",'businessId',b.id,'businessName',b.name,
               'location',b.location,'cityId',b."cityId",'parking',v."commonParking") AS details, r.package
           FROM business_halls h JOIN businesses b ON b.id=h."businessId"
           JOIN business_hall_package_revisions r ON r.id=h."packageRevisionId"
           LEFT JOIN business_hall_venue v ON v."businessId"=b.id
           WHERE h.id=$1 AND h."listingActive" AND h."packageSaved" AND h."archivedAt" IS NULL
             AND b.type='SERVICE' AND b."serviceType"='HALL' AND b.status='VERIFIED'"#,
    )
    .bind(hall)
    .fetch_optional(conn)
    .await?
    .ok_or_else(|| AppError::NotFound("Hall is no longer listed".into()))?;
    Ok((row.get("details"), row.get("package")))
}

fn slot_interval(offer: &Value, day: NaiveDate) -> Option<Interval> {
    if offer["enabled"].as_bool() == Some(false) {
        return None;
    }
    let to_utc = |key: &str| {
        let time = NaiveTime::parse_from_str(offer[key].as_str()?, "%H:%M").ok()?;
        FixedOffset::east_opt(19800)?
            .from_local_datetime(&day.and_time(time))
            .single()
            .map(|date| date.with_timezone(&Utc))
    };
    Interval::new(to_utc("hallFrom")?, to_utc("hallTo")?).ok()
}

fn rent(offer: &Value, with_ac: bool) -> Option<i64> {
    let (enabled, price, discount) = if with_ac {
        ("offerAc", "priceAc", "discountAcPct")
    } else {
        ("offerNoAc", "priceNoAc", "discountNoAcPct")
    };
    if !offer[enabled].as_bool().unwrap_or(!with_ac) {
        return None;
    }
    let percent = offer[discount].as_i64().unwrap_or(0).clamp(0, 99);
    offer[price]
        .as_i64()
        .map(|base| (base * (100 - percent) + 50) / 100)
}

async fn check_slot(
    conn: &mut PgConnection,
    business: Uuid,
    hall: Uuid,
    package: &Value,
    interval: Interval,
) -> AppResult<()> {
    if interval.start <= Utc::now() {
        return Err(AppError::Conflict("That slot has already started".into()));
    }
    ensure_package_window(Some(package), interval.start)?;
    availability_check(conn, business, Some(hall), interval, None).await
}

pub(crate) async fn requested_slot(
    conn: &mut PgConnection,
    business: Uuid,
    guests: i32,
    interval: Interval,
    request: &Value,
) -> AppResult<Value> {
    let hall: Uuid = serde_json::from_value(request["hallId"].clone())
        .map_err(|_| AppError::BadRequest("Choose a hall".into()))?;
    let (details, package) = listed_hall(conn, hall).await?;
    if details["businessId"] != json!(business) {
        return Err(AppError::BadRequest("Choose a hall from this venue".into()));
    }
    let day = interval
        .start
        .with_timezone(&FixedOffset::east_opt(19800).unwrap())
        .date_naive();
    let offer = package["slotOffers"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|offer| {
            offer["id"] == request["slotId"]
                && slot_interval(offer, day)
                    .is_some_and(|slot| slot.start == interval.start && slot.end == interval.end)
        })
        .ok_or_else(|| AppError::Conflict("This hall slot changed. Choose it again.".into()))?;
    let with_ac = request["withAc"]
        .as_bool()
        .ok_or_else(|| AppError::BadRequest("Choose a slot price".into()))?;
    let estimate = rent(offer, with_ac)
        .ok_or_else(|| AppError::Conflict("That pricing option is unavailable".into()))?;
    if package["capacity"]["seat"]
        .as_i64()
        .is_some_and(|seat| seat > 0 && seat < i64::from(guests))
    {
        return Err(AppError::BadRequest(
            "Guest count exceeds the hall seating capacity".into(),
        ));
    }
    check_slot(conn, business, hall, &package, interval).await?;
    Ok(
        json!({"kind":"HALL","hallId":hall,"hallName":details["hallName"],"slot":offer["label"],
        "withAc":with_ac,"estimate":estimate,"payment":package["payment"],
        "cancelRules":package["cancelRules"],"rescheduleRules":package["rescheduleRules"]}),
    )
}
