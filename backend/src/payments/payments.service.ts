import { Injectable, BadRequestException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Payment-gateway stub service (Phase 5 — credential-blocked).
 *
 * PhonePe / UPI gateway integration is intentionally NOT live: no merchant
 * credentials are configured yet. This service reports gateway readiness and
 * returns a clear "needs API key" state instead of faking transactions.
 *
 * // TODO: needs PhonePe API key — set PHONEPE_MERCHANT_ID, PHONEPE_SALT_KEY,
 * //       PHONEPE_SALT_INDEX env vars, then implement the real /pg/v1/pay
 * //       call + server-to-server callback verification here.
 */
@Injectable()
export class PaymentsService {
  constructor(private readonly config: ConfigService) {}

  /** True only when all PhonePe merchant credentials are present. */
  private get phonepeConfigured(): boolean {
    return Boolean(
      this.config.get<string>('PHONEPE_MERCHANT_ID') &&
        this.config.get<string>('PHONEPE_SALT_KEY'),
    );
  }

  /**
   * Gateway readiness for the client payment-method picker.
   * The Flutter app uses this to render UPI/PhonePe as live vs.
   * "setup pending" without hard-coding the state client-side.
   */
  getGatewayStatus() {
    return {
      wallet: { available: true },
      cash: { available: true },
      upi: {
        available: this.phonepeConfigured,
        provider: 'PHONEPE',
        needsApiKey: !this.phonepeConfigured,
        message: this.phonepeConfigured
          ? null
          : 'PhonePe gateway not configured — merchant API key required',
      },
    };
  }

  /**
   * UPI payment initiation — stubbed until credentials exist.
   * Never fakes a success: when unconfigured it returns an explicit
   * needs-API-key payload (HTTP 200 so clients can branch on it cleanly).
   */
  initiateUpiPayment(userId: string, body: { amount?: number; bookingId?: string }) {
    const amount = Number(body?.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new BadRequestException('A positive amount is required');
    }

    if (!this.phonepeConfigured) {
      // TODO: needs PhonePe API key — replace this stub with the real
      // PhonePe Pay API request once merchant credentials are provided.
      return {
        status: 'UNAVAILABLE',
        needsApiKey: true,
        provider: 'PHONEPE',
        message:
          'UPI payments are not live yet: the PhonePe merchant API key has not been configured. Choose Wallet or Cash instead.',
      };
    }

    // Credentials exist but the real integration is still to be written —
    // refuse rather than pretend the charge happened.
    return {
      status: 'NOT_IMPLEMENTED',
      needsApiKey: false,
      provider: 'PHONEPE',
      message:
        'PhonePe credentials detected, but the gateway call is not implemented yet.',
    };
  }
}
