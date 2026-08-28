import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { isRealSecret } from '../common/env-secrets';

/**
 * MSG91 OTP SMS delivery for login / booking OTPs.
 *
 * Gixbee generates and verifies OTPs in Redis; MSG91 only delivers the SMS.
 * Requires MSG91_AUTH_KEY + MSG91_TEMPLATE_ID (DLT-approved template with a
 * single {#var#} or ##OTP## slot for the 6-digit code).
 */
@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);

  constructor(private readonly config: ConfigService) {}

  isConfigured(): boolean {
    return (
      isRealSecret(this.config.get<string>('MSG91_AUTH_KEY')) &&
      isRealSecret(this.config.get<string>('MSG91_TEMPLATE_ID'))
    );
  }

  /** Normalize to MSG91 mobile format: 91XXXXXXXXXX (no +). */
  normalizeMobile(phone: string): string {
    const digits = phone.replace(/\D/g, '');
    if (digits.length === 10) return `91${digits}`;
    if (digits.length === 12 && digits.startsWith('91')) return digits;
    if (digits.length === 13 && digits.startsWith('091')) return digits.slice(1);
    return digits;
  }

  /**
   * Send a login OTP via MSG91 v5 Flow API (template variable OTP).
   * No-op with a dev log when unconfigured and NODE_ENV !== production.
   */
  async sendOtp(phone: string, otp: string): Promise<void> {
    if (!this.isConfigured()) {
      if (this.config.get('NODE_ENV') === 'production') {
        this.logger.error(
          '[MSG91] SMS not configured — OTP was NOT delivered (set MSG91_AUTH_KEY + MSG91_TEMPLATE_ID)',
        );
      }
      return;
    }

    const authKey = this.config.get<string>('MSG91_AUTH_KEY')!.trim();
    const templateId = this.config.get<string>('MSG91_TEMPLATE_ID')!.trim();
    const senderId = this.config.get<string>('MSG91_SENDER_ID')?.trim();
    const mobile = this.normalizeMobile(phone);

    const body: Record<string, unknown> = {
      template_id: templateId,
      short_url: '0',
      recipients: [
        {
          mobiles: mobile,
          OTP: otp,
          otp,
        },
      ],
    };
    if (senderId) body.sender = senderId;

    const res = await fetch('https://control.msg91.com/api/v5/flow/', {
      method: 'POST',
      headers: {
        authkey: authKey,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      this.logger.error(
        `[MSG91] OTP send failed (${res.status}) for ${mobile}: ${text.slice(0, 200)}`,
      );
      throw new Error('SMS delivery failed');
    }

    this.logger.log(`[MSG91] OTP sent to ${mobile}`);
  }
}
