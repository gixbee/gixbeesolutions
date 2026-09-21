use crate::error::{AppError, AppResult};
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
        {
            return Err(AppError::BadRequest(
                "Provide a name, positive rental rates and a valid minimum duration".into(),
            ));
        }
        parse_pin(value.pickup_lat, value.pickup_lng)?;
        Ok(value)
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
}
