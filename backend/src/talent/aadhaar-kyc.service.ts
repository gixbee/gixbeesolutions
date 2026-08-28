import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { isRealSecret } from '../common/env-secrets';

export interface AadhaarGenerateResult {
  clientId: string;
  message: string;
}

export interface AadhaarVerifyResult {
  maskedAadhaar: string;
  fullName: string;
}

/**
 * Surepass Aadhaar OTP eKYC (credential-blocked until keys exist).
 *
 * Env:
 *   AADHAAR_CLIENT_ID / AADHAAR_CLIENT_SECRET — Surepass API credentials
 *   AADHAAR_API_BASE — optional; defaults to sandbox in dev, production URL
 *                      when NODE_ENV=production
 *
 * We never persist the full Aadhaar number — only a masked reference after
 * successful verification (UIDAI storage rules).
 */
@Injectable()
export class AadhaarKycService {
  private readonly logger = new Logger(AadhaarKycService.name);

  constructor(private readonly config: ConfigService) {}

  isConfigured(): boolean {
    return (
      isRealSecret(this.config.get<string>('AADHAAR_CLIENT_ID')) &&
      isRealSecret(this.config.get<string>('AADHAAR_CLIENT_SECRET'))
    );
  }

  private get apiBase(): string {
    const override = this.config.get<string>('AADHAAR_API_BASE')?.trim();
    if (override) return override.replace(/\/$/, '');
    return this.config.get('NODE_ENV') === 'production'
      ? 'https://kyc-api.surepass.app'
      : 'https://sandbox.surepass.app';
  }

  private get bearerToken(): string {
    return this.config.get<string>('AADHAAR_CLIENT_SECRET')!.trim();
  }

  private async post<T>(path: string, body: Record<string, unknown>): Promise<T> {
    const res = await fetch(`${this.apiBase}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        Authorization: `Bearer ${this.bearerToken}`,
      },
      body: JSON.stringify(body),
    });
    const json = (await res.json().catch(() => ({}))) as Record<string, any>;
    if (!res.ok || json.success === false) {
      const msg =
        json.message ??
        json.error ??
        `Aadhaar KYC request failed (${res.status})`;
      this.logger.warn(`[AadhaarKYC] ${path} failed: ${msg}`);
      throw new BadRequestException(msg);
    }
    return json as T;
  }

  async generateOtp(aadhaarNumber: string): Promise<AadhaarGenerateResult> {
    if (!this.isConfigured()) {
      throw new ServiceUnavailableException(
        'Aadhaar verification is not configured — set AADHAAR_CLIENT_ID / AADHAAR_CLIENT_SECRET',
      );
    }
    const id = aadhaarNumber.replace(/\D/g, '');
    if (!/^\d{12}$/.test(id)) {
      throw new BadRequestException('Aadhaar number must be 12 digits');
    }

    const json = await this.post<{
      data?: { client_id?: string };
      client_id?: string;
      message?: string;
    }>('/api/v1/aadhaar-v2/generate-otp', { id_number: id });

    const clientId = json.data?.client_id ?? json.client_id;
    if (!clientId) {
      throw new BadRequestException('Aadhaar OTP could not be initiated');
    }

    return {
      clientId,
      message:
        json.message ??
        'OTP sent to your Aadhaar-linked mobile. Enter it to complete verification.',
    };
  }

  async submitOtp(clientId: string, otp: string): Promise<AadhaarVerifyResult> {
    if (!this.isConfigured()) {
      throw new ServiceUnavailableException(
        'Aadhaar verification is not configured',
      );
    }
    if (!clientId?.trim() || !/^\d{6}$/.test(otp)) {
      throw new BadRequestException('clientId and a 6-digit OTP are required');
    }

    const json = await this.post<{
      data?: {
        full_name?: string;
        name?: string;
        masked_aadhaar?: string;
        maskedNumber?: string;
      };
    }>('/api/v1/aadhaar-v2/submit-otp', {
      client_id: clientId.trim(),
      otp,
    });

    const data = json.data ?? {};
    const fullName = data.full_name ?? data.name ?? '';
    const maskedAadhaar = data.masked_aadhaar ?? data.maskedNumber ?? 'XXXX-XXXX-XXXX';
    if (!fullName) {
      throw new BadRequestException('Aadhaar verification did not return identity data');
    }

    return { maskedAadhaar, fullName };
  }
}
