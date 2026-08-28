import { BadRequestException } from '@nestjs/common';
import { PaymentsService } from './payments.service';
import { WALLET_PAYMENTS_ENABLED } from '../common/money-model';

/**
 * Unit tests for PaymentsService gateway readiness + wallet-recharge gate.
 * Order creation / webhook paths need repos and fetch — covered separately
 * when wired; here we assert the money-model contract the app picker reads.
 */
function makeService(env: Record<string, string | undefined> = {}) {
  const config: any = {
    get: jest.fn((key: string) => env[key]),
  };
  const ordersRepo: any = {
    create: jest.fn((row: any) => row),
    save: jest.fn(async (row: any) => row),
    update: jest.fn(async () => ({ affected: 0 })),
    findOne: jest.fn(async () => null),
  };
  return new PaymentsService(
    config,
    ordersRepo,
    {} as any,
    {} as any,
    {} as any,
    {} as any,
    {} as any, // MatchingService (forwardRef)
  );
}

describe('PaymentsService.getGatewayStatus', () => {
  it('reports wallet from the money-model flag and cash always available', () => {
    const status = makeService({}).getGatewayStatus();

    expect(status.wallet.available).toBe(WALLET_PAYMENTS_ENABLED);
    expect(status.cash.available).toBe(true);
  });

  it('reports Razorpay unavailable with needsApiKey when creds are absent', () => {
    const status = makeService({}).getGatewayStatus();

    expect(status.razorpay.available).toBe(false);
    expect(status.razorpay.needsApiKey).toBe(true);
    expect(status.razorpay.message).toContain('RAZORPAY');
  });

  it('treats a partial credential set (key id only) as unconfigured', () => {
    const status = makeService({
      RAZORPAY_KEY_ID: 'rzp_test_x',
    }).getGatewayStatus();

    expect(status.razorpay.available).toBe(false);
    expect(status.razorpay.needsApiKey).toBe(true);
  });

  it('reports Razorpay available when both key id and secret are present', () => {
    const status = makeService({
      RAZORPAY_KEY_ID: 'rzp_test_x',
      RAZORPAY_KEY_SECRET: 'secret',
    }).getGatewayStatus();

    expect(status.razorpay.available).toBe(true);
    expect(status.razorpay.needsApiKey).toBe(false);
    expect(status.razorpay.message).toBeNull();
  });

  it('treats placeholder Razorpay keys as unconfigured', () => {
    const status = makeService({
      RAZORPAY_KEY_ID: 'placeholder_key_id',
      RAZORPAY_KEY_SECRET: 'placeholder_key_secret',
    }).getGatewayStatus();

    expect(status.razorpay.available).toBe(false);
    expect(status.razorpay.needsApiKey).toBe(true);
  });

  it('keeps legacy upi field as unavailable PhonePe stub', () => {
    const status = makeService({}).getGatewayStatus();
    expect(status.upi.available).toBe(false);
    expect(status.upi.provider).toBe('PHONEPE');
    expect(status.upi.needsApiKey).toBe(true);
  });
});

describe('PaymentsService.createRechargeOrder', () => {
  it('rejects wallet recharge when wallet payments are disabled', async () => {
    if (WALLET_PAYMENTS_ENABLED) return;
    const service = makeService({
      RAZORPAY_KEY_ID: 'rzp_test_x',
      RAZORPAY_KEY_SECRET: 'secret',
    });
    await expect(service.createRechargeOrder('u1', 100)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});
