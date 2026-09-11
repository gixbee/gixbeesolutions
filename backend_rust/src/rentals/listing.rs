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
        {
            return Err(AppError::BadRequest(
                "Provide a name, positive rental rates and a valid minimum duration".into(),
            ));
        }
        Ok(value)
    }
    pub fn hourly(&self) -> Decimal {
        Decimal::from_f64_retain(self.hourly_rate)
            .unwrap()
            .round_dp(2)
    }
    pub fn delivery(&self)->Decimal {Decimal::from_f64_retain(self.delivery_fee).unwrap().round_dp(2)}
    pub fn deposit(&self)->Decimal {Decimal::from_f64_retain(self.deposit_per_unit).unwrap().round_dp(2)}
    pub fn daily(&self) -> Option<Decimal> {
        self.daily_rate
            .map(|r| Decimal::from_f64_retain(r).unwrap().round_dp(2))
    }
}
