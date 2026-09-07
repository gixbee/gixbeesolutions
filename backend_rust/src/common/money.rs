//! Gixbee money model — mirrors backend/src/common/money-model.ts

pub const WALLET_PAYMENTS_ENABLED: bool = false;
pub const DEFAULT_BOOKING_PAYMENT_METHOD: &str = "CASH";
pub const NEW_USER_WALLET_BONUS: f64 = if WALLET_PAYMENTS_ENABLED { 30.0 } else { 0.0 };

pub struct WalletPaymentsDisabledError {
    pub action: String,
}

impl std::fmt::Display for WalletPaymentsDisabledError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Wallet payments are disabled ({}). Jobs settle via cash/UPI dual-confirm; Gixbee fees use direct Razorpay.",
            self.action
        )
    }
}

impl std::error::Error for WalletPaymentsDisabledError {}

pub fn assert_wallet_payments_enabled(action: &str) -> Result<(), WalletPaymentsDisabledError> {
    if WALLET_PAYMENTS_ENABLED {
        Ok(())
    } else {
        Err(WalletPaymentsDisabledError {
            action: action.to_string(),
        })
    }
}
