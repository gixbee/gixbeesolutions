use crate::error::{AppError, AppResult};
use chrono::{DateTime, Datelike, FixedOffset, NaiveDate, Timelike, Utc};
use rust_decimal::Decimal;
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Listing {
    pub name: String,
    pub description: Option<String>,
    pub image_url: Option<String>,
    #[serde(default)]
    pub image_urls: Vec<String>,
    pub hourly_rate: f64,
    pub daily_rate: Option<f64>,
    #[serde(default = "one")]
    pub min_hours_to_rent: i32,
    #[serde(default = "yes")]
    pub is_available: bool,
    pub business_id: Option<uuid::Uuid>,
    #[serde(default = "one")]
    pub quantity: i32,
    #[serde(default)]
    pub pickup_address: String,
    #[serde(default)]
    pub delivery_available: bool,
    #[serde(default)]
    pub delivery_fee: f64,
    #[serde(default)]
    pub deposit_per_unit: f64,
    #[serde(default)]
    pub pickup_lat: Option<f64>,
    #[serde(default)]
    pub pickup_lng: Option<f64>,
    #[serde(default)]
    pub advance_amount: f64,
    #[serde(default)]
    pub advance_percent: f64,
    #[serde(default)]
    pub pickup_instructions: String,
    #[serde(default)]
    pub late_fee_per_hour: f64,
    #[serde(default = "good")]
    pub condition: String,
    #[serde(default = "other")]
    pub category: String,
    #[serde(default = "flexible")]
    pub cancellation_policy: String,
    #[serde(default)]
    pub available_from: Option<NaiveDate>,
    #[serde(default)]
    pub available_until: Option<NaiveDate>,
    #[serde(default = "all_weekdays")]
    pub available_weekdays: Vec<i16>,
    #[serde(default)]
    pub slot_start_minute: Option<i32>,
    #[serde(default)]
    pub slot_end_minute: Option<i32>,
}

pub const DEFAULT_RENTAL_RADIUS_KM: f64 = 25.0;
pub const MAX_RENTAL_RADIUS_KM: f64 = 50.0;

pub fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    let r = 6371.0;
    let d_lat = (lat2 - lat1).to_radians();
    let d_lng = (lng2 - lng1).to_radians();
    let a = (d_lat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (d_lng / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    r * c
}

pub fn parse_pin(lat: Option<f64>, lng: Option<f64>) -> Result<Option<(f64, f64)>, crate::error::AppError> {
    match (lat, lng) {
        (None, None) => Ok(None),
        (Some(a), Some(b))
            if a.is_finite()
                && b.is_finite()
                && (-90.0..=90.0).contains(&a)
                && (-180.0..=180.0).contains(&b) =>
        {
            Ok(Some((a, b)))
        }
        _ => Err(crate::error::AppError::BadRequest(
            "Pickup location is invalid".into(),
        )),
    }
}

/// Visible when the listing is in the customer's city, or the pickup pin is
/// within [radius_km] of their GPS (cross-city spillover).
pub fn is_nearby(
    user_lat: f64,
    user_lng: f64,
    user_city: Option<uuid::Uuid>,
    pin: Option<(f64, f64)>,
    item_city: Option<uuid::Uuid>,
    radius_km: f64,
) -> bool {
    if user_city.is_some() && user_city == item_city {
        return true;
    }
    match pin {
        Some((plat, plng)) => haversine_km(user_lat, user_lng, plat, plng) <= radius_km,
        None => false,
    }
}

pub fn catalog_bbox(lat: f64, lng: f64, radius_km: f64) -> (f64, f64, f64, f64) {
    let lat_delta = radius_km / 111.0;
    let cos_lat = lat.to_radians().cos().abs().max(0.01);
    let lng_delta = radius_km / (111.0 * cos_lat);
    (
        (lat - lat_delta).clamp(-90.0, 90.0),
        (lat + lat_delta).clamp(-90.0, 90.0),
        (lng - lng_delta).clamp(-180.0, 180.0),
        (lng + lng_delta).clamp(-180.0, 180.0),
    )
}

pub fn parse_radius_km(raw: Option<&str>) -> f64 {
    raw.and_then(|s| s.parse::<f64>().ok())
        .filter(|v| v.is_finite() && *v > 0.0)
        .map(|v| v.min(MAX_RENTAL_RADIUS_KM))
        .unwrap_or(DEFAULT_RENTAL_RADIUS_KM)
}
fn one() -> i32 {
    1
}
fn yes() -> bool {
    true
}
fn good() -> String {
    "GOOD".into()
}
fn other() -> String {
    "OTHER".into()
}
fn flexible() -> String {
    "FLEXIBLE".into()
}
fn all_weekdays() -> Vec<i16> {
    vec![1, 2, 3, 4, 5, 6, 7]
}

const CATEGORIES: &[&str] = &[
    "TOOLS", "DRILL", "CAMERA", "FURNITURE", "VEHICLE", "ELECTRONICS", "PARTY", "SPORTS", "OTHER",
];
const CONDITIONS: &[&str] = &["NEW", "GOOD", "USED"];
const POLICIES: &[&str] = &["FLEXIBLE", "MODERATE", "STRICT", "NON_REFUNDABLE"];

fn ist(dt: DateTime<Utc>) -> DateTime<FixedOffset> {
    dt.with_timezone(&FixedOffset::east_opt(5 * 3600 + 30 * 60).unwrap())
}

/// Owner-defined calendar: date range, weekdays (ISO 1=Mon), optional daily hours.
pub fn listing_window_ok(
    from: Option<NaiveDate>,
    until: Option<NaiveDate>,
    weekdays: &[i16],
    slot_start: Option<i32>,
    slot_end: Option<i32>,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
) -> AppResult<()> {
    let start_ist = ist(start);
    let end_ist = ist(end);
    let start_day = start_ist.date_naive();
    let end_day = end_ist.date_naive();
    if from.is_some_and(|d| start_day < d) || until.is_some_and(|d| end_day > d) {
        return Err(AppError::BadRequest(
            "This item is not available on the selected dates".into(),
        ));
    }
    let days = if weekdays.is_empty() {
        all_weekdays()
    } else {
        weekdays.to_vec()
    };
    let mut day = start_day;
    while day <= end_day {
        let wd = day.weekday().number_from_monday() as i16;
        if !days.contains(&wd) {
            return Err(AppError::BadRequest(
                "This item is not available on one of the selected days".into(),
            ));
        }
        day = day
            .succ_opt()
            .ok_or_else(|| AppError::BadRequest("Invalid rental dates".into()))?;
    }
    if let (Some(open), Some(close)) = (slot_start, slot_end) {
        let start_min = (start_ist.num_seconds_from_midnight() / 60) as i32;
        let end_min = (end_ist.num_seconds_from_midnight() / 60) as i32;
        if start_min < open || start_min > close || end_min < open || end_min > close {
            return Err(AppError::BadRequest(
                "Pickup and return must fall inside the store's listed hours".into(),
            ));
        }
    }
    Ok(())
}
impl Listing {
    pub fn parse(body: &Value) -> AppResult<Self> {
        let mut value: Self = serde_json::from_value(body.clone())
            .map_err(|_| AppError::BadRequest("Invalid rental listing fields".into()))?;
        value.name = value.name.trim().to_string();
        value.normalize_photos();
        if value.name.is_empty()
            || value.name.len() > 200
            || !(0.01..=99_999_999.0).contains(&value.hourly_rate)
            || value
                .daily_rate
                .is_some_and(|r| !(0.01..=99_999_999.0).contains(&r))
            || !(1..=24 * 366).contains(&value.min_hours_to_rent)
            || !(1..=100000).contains(&value.quantity)
            || value.pickup_address.len()>2000
            || !(0.0..=99_999_999.0).contains(&value.delivery_fee)
            || !(0.0..=99_999_999.0).contains(&value.deposit_per_unit)
            || !(0.0..=99_999_999.0).contains(&value.advance_amount)
            || !(0.0..=100.0).contains(&value.advance_percent)
            || !(0.0..=99_999_999.0).contains(&value.late_fee_per_hour)
            || value.pickup_instructions.len() > 280
        {
            return Err(AppError::BadRequest(
                "Provide a name, positive rental rates and a valid minimum duration".into(),
            ));
        }
        value.condition = value.condition.trim().to_uppercase();
        value.category = value.category.trim().to_uppercase();
        value.cancellation_policy = value.cancellation_policy.trim().to_uppercase();
        value.pickup_instructions = value.pickup_instructions.trim().to_string();
        if !CONDITIONS.contains(&value.condition.as_str())
            || !CATEGORIES.contains(&value.category.as_str())
            || !POLICIES.contains(&value.cancellation_policy.as_str())
        {
            return Err(AppError::BadRequest(
                "Choose a valid category, condition and cancellation policy".into(),
            ));
        }
        let mut days: Vec<i16> = value
            .available_weekdays
            .iter()
            .copied()
            .filter(|d| (1..=7).contains(d))
            .collect();
        days.sort_unstable();
        days.dedup();
        if days.is_empty() {
            days = all_weekdays();
        }
        value.available_weekdays = days;
        if value
            .available_from
            .zip(value.available_until)
            .is_some_and(|(a, b)| a > b)
        {
            return Err(AppError::BadRequest(
                "Available-from cannot be after available-until".into(),
            ));
        }
        match (value.slot_start_minute, value.slot_end_minute) {
            (None, None) => {}
            (Some(a), Some(b)) if (0..1440).contains(&a) && (1..=1440).contains(&b) && b > a => {}
            _ => {
                return Err(AppError::BadRequest(
                    "Set both pickup hours, with end after start".into(),
                ));
            }
        }
        if !value.delivery_available {
            value.delivery_fee = 0.0;
        }
        parse_pin(value.pickup_lat, value.pickup_lng)?;
        Ok(value)
    }
    pub fn late_fee(&self) -> Decimal {
        Decimal::from_f64_retain(self.late_fee_per_hour)
            .unwrap()
            .round_dp(2)
    }
    pub fn percent(&self) -> Decimal {
        Decimal::from_f64_retain(self.advance_percent)
            .unwrap()
            .round_dp(2)
    }
    pub fn hourly(&self) -> Decimal {
        Decimal::from_f64_retain(self.hourly_rate)
            .unwrap()
            .round_dp(2)
    }
    pub fn delivery(&self)->Decimal {Decimal::from_f64_retain(self.delivery_fee).unwrap().round_dp(2)}
    pub fn deposit(&self)->Decimal {Decimal::from_f64_retain(self.deposit_per_unit).unwrap().round_dp(2)}
    pub fn advance(&self)->Decimal {Decimal::from_f64_retain(self.advance_amount).unwrap().round_dp(2)}
    pub fn daily(&self) -> Option<Decimal> {
        self.daily_rate
            .map(|r| Decimal::from_f64_retain(r).unwrap().round_dp(2))
    }
    pub fn image_urls_json(&self) -> Value {
        Value::Array(
            self.image_urls
                .iter()
                .map(|u| Value::String(u.clone()))
                .collect(),
        )
    }
    fn normalize_photos(&mut self) {
        const MAX: usize = 6;
        let mut urls = Vec::new();
        let mut push = |raw: &str| {
            let t = raw.trim();
            if t.is_empty() || t.len() > 2000 || urls.iter().any(|u| u == t) || urls.len() >= MAX
            {
                return;
            }
            if !(t.starts_with('/') || t.starts_with("https://") || t.starts_with("http://")) {
                return;
            }
            urls.push(t.to_string());
        };
        if let Some(cover) = &self.image_url {
            push(cover);
        }
        for extra in &self.image_urls {
            push(extra);
        }
        self.image_url = urls.first().cloned();
        self.image_urls = urls;
    }
}

#[cfg(test)]
mod tests {
    use super::Listing;
    use serde_json::json;

    fn base() -> serde_json::Value {
        json!({
            "name": "Bosch drill",
            "hourlyRate": 100.0,
            "pickupAddress": "Shop 1"
        })
    }

    #[test]
    fn keeps_cover_then_gallery_and_caps_at_six() {
        let mut body = base();
        body["imageUrl"] = json!("/uploads/a.jpg");
        body["imageUrls"] = json!([
            "/uploads/a.jpg",
            "/uploads/b.jpg",
            "/uploads/c.jpg",
            "/uploads/d.jpg",
            "/uploads/e.jpg",
            "/uploads/f.jpg",
            "/uploads/g.jpg"
        ]);
        let listing = Listing::parse(&body).unwrap();
        assert_eq!(listing.image_url.as_deref(), Some("/uploads/a.jpg"));
        assert_eq!(listing.image_urls.len(), 6);
        assert_eq!(listing.image_urls[1], "/uploads/b.jpg");
        assert!(!listing.image_urls.iter().any(|u| u.ends_with("g.jpg")));
    }

    #[test]
    fn drops_empty_and_non_http_paths() {
        let mut body = base();
        body["imageUrls"] = json!(["", "  ", "javascript:alert(1)", "/uploads/ok.jpg"]);
        let listing = Listing::parse(&body).unwrap();
        assert_eq!(listing.image_urls, vec!["/uploads/ok.jpg"]);
        assert_eq!(listing.image_url.as_deref(), Some("/uploads/ok.jpg"));
    }

    #[test]
    fn rejects_partial_pickup_coordinates() {
        let mut body = base();
        body["pickupLat"] = json!(17.4);
        assert!(Listing::parse(&body).is_err());
    }

    #[test]
    fn keeps_valid_pickup_coordinates() {
        let mut body = base();
        body["pickupLat"] = json!(17.385);
        body["pickupLng"] = json!(78.486);
        let listing = Listing::parse(&body).unwrap();
        assert_eq!(listing.pickup_lat, Some(17.385));
        assert_eq!(listing.pickup_lng, Some(78.486));
    }

    #[test]
    fn keeps_a_store_advance_amount() {
        let mut body = base();
        body["advanceAmount"] = json!(150.5);
        let listing = Listing::parse(&body).unwrap();
        assert_eq!(listing.advance_amount, 150.5);
        assert_eq!(listing.advance().to_string(), "150.50");
    }

    #[test]
    fn same_city_is_nearby_even_when_the_pin_is_far() {
        let city = uuid::Uuid::nil();
        assert!(super::is_nearby(
            17.4,
            78.5,
            Some(city),
            Some((18.5, 79.5)),
            Some(city),
            25.0
        ));
    }

    #[test]
    fn other_city_counts_when_the_pin_is_within_radius() {
        let user_city = uuid::Uuid::nil();
        let other = uuid::Uuid::from_u128(1);
        // ~11 km north of 17.4, 78.5
        assert!(super::is_nearby(
            17.4,
            78.5,
            Some(user_city),
            Some((17.5, 78.5)),
            Some(other),
            25.0
        ));
        assert!(!super::is_nearby(
            17.4,
            78.5,
            Some(user_city),
            Some((18.1, 78.5)),
            Some(other),
            25.0
        ));
    }

    #[test]
    fn listings_without_city_or_pin_stay_hidden() {
        assert!(!super::is_nearby(17.4, 78.5, None, None, None, 25.0));
    }

    #[test]
    fn pickup_pin_finds_a_store_that_has_no_city() {
        assert!(super::is_nearby(
            8.576,
            76.926,
            None,
            Some((8.577, 76.926)),
            None,
            25.0
        ));
    }

    #[test]
    fn defaults_category_condition_and_flexible_cancel() {
        let listing = Listing::parse(&base()).unwrap();
        assert_eq!(listing.category, "OTHER");
        assert_eq!(listing.condition, "GOOD");
        assert_eq!(listing.cancellation_policy, "FLEXIBLE");
        assert_eq!(listing.available_weekdays, vec![1, 2, 3, 4, 5, 6, 7]);
        assert_eq!(listing.delivery_fee, 0.0);
    }

    #[test]
    fn zeros_delivery_charge_when_delivery_is_off() {
        let mut body = base();
        body["deliveryAvailable"] = json!(false);
        body["deliveryFee"] = json!(199);
        let listing = Listing::parse(&body).unwrap();
        assert_eq!(listing.delivery_fee, 0.0);
    }

    #[test]
    fn rejects_unknown_category() {
        let mut body = base();
        body["category"] = json!("SPACESHIP");
        assert!(Listing::parse(&body).is_err());
    }

    fn ist_window(start: &str, end: &str) -> (chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>) {
        (
            chrono::DateTime::parse_from_rfc3339(start)
                .unwrap()
                .with_timezone(&chrono::Utc),
            chrono::DateTime::parse_from_rfc3339(end)
                .unwrap()
                .with_timezone(&chrono::Utc),
        )
    }

    #[test]
    fn weekday_window_blocks_sunday_when_weekdays_are_mon_sat() {
        // Friday 10:00-12:00 IST is allowed; Sunday is not.
        let (fri_s, fri_e) = ist_window("2026-10-02T10:00:00+05:30", "2026-10-02T12:00:00+05:30");
        let (sun_s, sun_e) = ist_window("2026-10-04T10:00:00+05:30", "2026-10-04T12:00:00+05:30");
        let days = vec![1, 2, 3, 4, 5, 6];
        assert!(super::listing_window_ok(None, None, &days, None, None, fri_s, fri_e).is_ok());
        assert!(super::listing_window_ok(None, None, &days, None, None, sun_s, sun_e).is_err());
    }

    #[test]
    fn daily_hours_must_cover_pickup_and_return() {
        let (ok_s, ok_e) = ist_window("2026-10-02T10:00:00+05:30", "2026-10-02T17:00:00+05:30");
        let (late_s, late_e) = ist_window("2026-10-02T10:00:00+05:30", "2026-10-02T19:00:00+05:30");
        assert!(super::listing_window_ok(None, None, &[1, 2, 3, 4, 5, 6, 7], Some(9 * 60), Some(18 * 60), ok_s, ok_e).is_ok());
        assert!(super::listing_window_ok(None, None, &[1, 2, 3, 4, 5, 6, 7], Some(9 * 60), Some(18 * 60), late_s, late_e).is_err());
    }
}
