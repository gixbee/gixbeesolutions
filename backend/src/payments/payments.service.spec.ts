import { BadRequestException } from '@nestjs/common';
import { PaymentsService } from './payments.service';

/**
 * Unit tests for the credential-blocked payment-gateway stub.
 *
 * The contract under test: the service must report gateway readiness
 * truthfully from env config and must NEVER fake a successful charge —
 * unconfigured → explicit needs-API-key payload, configured-but-unbuilt →
 * explicit NOT_IMPLEMENTED.
 */
function makeService(env: Record<string, string | undefined>) {
  const config: any = {
    get: jest.fn((key: string) => env[key]),
  };
  return new PaymentsService(config);
}

describe('PaymentsService.getGatewayStatus', () => {
  it('reports UPI unavailable with needsApiKey when PhonePe creds are absent', () => {
    const status = makeService({}).getGatewayStatus();

    expect(status.wallet.available).toBe(true);
    expect(status.cash.available).toBe(true);
    expect(status.upi.available).toBe(false);
    expect(status.upi.needsApiKey).toBe(true);
    expect(status.upi.provider).toBe('PHONEPE');
    expect(status.upi.message).toContain('not configured');
  });

  it('treats a partial credential set (merchant id only) as unconfigured', () => {
    const status = makeService({
      PHONEPE_MERCHANT_ID: 'M123',
    }).getGatewayStatus();

    expect(status.upi.available).toBe(false);
    expect(status.upi.needsApiKey).toBe(true);
  });

  it('reports UPI available with no message when both creds are present', () => {
    const status = makeService({
      PHONEPE_MERCHANT_ID: 'M123',
      PHONEPE_SALT_KEY: 'salt-abc',
    }).getGatewayStatus();

    expect(status.upi.available).toBe(true);
    expect(status.upi.needsApiKey).toBe(false);
    expect(status.upi.message).toBeNull();
  });
});

describe('PaymentsService.initiateUpiPayment', () => {
  it('rejects missing, zero, negative, and non-numeric amounts', () => {
    const service = makeService({});

    expect(() => service.initiateUpiPayment('u1', {})).toThrow(
      BadRequestException,
    );
    expect(() => service.initiateUpiPayment('u1', { amount: 0 })).toThrow(
      BadRequestException,
    );
    expect(() => service.initiateUpiPayment('u1', { amount: -50 })).toThrow(
      BadRequestException,
    );
    expect(() =>
      service.initiateUpiPayment('u1', { amount: NaN }),
    ).toThrow(BadRequestException);
  });

  it('returns an explicit UNAVAILABLE needs-API-key payload when unconfigured', () => {
    const res = makeService({}).initiateUpiPayment('u1', {
      amount: 250,
      bookingId: 'b1',
    });

    expect(res.status).toBe('UNAVAILABLE');
    expect(res.needsApiKey).toBe(true);
    expect(res.provider).toBe('PHONEPE');
    expect(res.message).toContain('not live');
  });

  it('refuses with NOT_IMPLEMENTED (never fakes a charge) when creds exist', () => {
    const res = makeService({
      PHONEPE_MERCHANT_ID: 'M123',
      PHONEPE_SALT_KEY: 'salt-abc',
    }).initiateUpiPayment('u1', { amount: 250 });

    expect(res.status).toBe('NOT_IMPLEMENTED');
    expect(res.needsApiKey).toBe(false);
    // The stub must never return a success-shaped payload.
    expect(res.status).not.toBe('SUCCESS');
  });
});
