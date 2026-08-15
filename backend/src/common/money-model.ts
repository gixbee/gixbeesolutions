/**
 * Gixbee money model — single source of truth.
 *
 * Flip {@link WALLET_PAYMENTS_ENABLED} to re-enable in-app wallet settlement.
 * Until then, do not invent new wallet charges or default `paymentMethod` to
 * `WALLET`. Settlement code behind the flag may stay for a product return.
 *
 * ## Live paths (wallet OFF)
 *
 * 1. **Job settlement (Instant Help + most bookings)**
 *    Customer pays the pro directly (cash / UPI outside the app).
 *    Worker + customer dual-confirm via `markPaid`. Gixbee never holds the
 *    job amount. Instant completion also freezes a one-way petrol charge
 *    (`acceptDistanceKm × instant_petrol_per_km`).
 *
 * 2. **Worker Go Live access**
 *    Job credits packs + periodic fee (`go_live_period_fee`) via **direct
 *    Razorpay** checkout (`PaymentPurpose.PERIOD_FEE`). Not a wallet hop.
 *    Accept cost is Master Entries `job_credit_per_accept` (default 15).
 *
 * 3. **Late-cancel compensation**
 *    After 3 strikes, customer pays distance-based compensation via
 *    **direct Razorpay** (`PaymentPurpose.LATE_CANCEL_COMPENSATION`).
 *    Unlocks Instant Help; amount is recorded for worker payout ops.
 *
 * 4. **Smart Hiring (Find a Job / Hire Employee)**
 *    Match fee (`HIRING_MATCH_FEE`, ₹49/99/199/399) and extra Job Type
 *    (`EXTRA_JOB_TYPE_FEE`, ₹50) via **direct Razorpay**. Guarantee CREDIT
 *    lands in `users.hiringCreditBalance` (applied to the next match fee),
 *    not the dormant wallet. REFUND uses the Razorpay refund API.
 *
 * ## Dormant paths (wallet ON only — `WALLET_PAYMENTS_ENABLED`)
 *
 * - Customer→worker wallet transfer on non-Instant completion
 * - Wallet reverse on cancel of a WALLET-settled booking
 * - Platform booking fee debit / first-job wallet bonus
 * - Wallet recharge Razorpay orders + first-recharge bonus
 * - Smart Hiring preference / request wallet `charge()` (legacy; Razorpay
 *   is the live path above while wallet is off)
 *
 * ## Defaults
 *
 * New bookings without an explicit method use {@link DEFAULT_BOOKING_PAYMENT_METHOD}
 * (`CASH`) so dual-confirm collection is the default, not a dead wallet path.
 */

/** Master switch — keep false until the wallet product ships again. */
export const WALLET_PAYMENTS_ENABLED = false;

/**
 * Stored on bookings when the client omits `paymentMethod`.
 * Must stay a direct-collection method while the wallet is off.
 */
export const DEFAULT_BOOKING_PAYMENT_METHOD = 'CASH';

/** New-user welcome balance. Zero while wallet product is off. */
export const NEW_USER_WALLET_BONUS = WALLET_PAYMENTS_ENABLED ? 30 : 0;

export function assertWalletPaymentsEnabled(action: string): void {
  if (WALLET_PAYMENTS_ENABLED) return;
  // Lazy import avoided — callers use Nest BadRequestException themselves
  // via the helper below when they need an HTTP error.
  throw new WalletPaymentsDisabledError(action);
}

export class WalletPaymentsDisabledError extends Error {
  constructor(action: string) {
    super(
      `Wallet payments are disabled (${action}). Jobs settle via cash/UPI dual-confirm; Gixbee fees use direct Razorpay.`,
    );
    this.name = 'WalletPaymentsDisabledError';
  }
}
