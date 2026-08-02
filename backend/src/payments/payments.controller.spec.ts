import { PaymentsController } from './payments.controller';

/**
 * Thin HTTP delegation surface over PaymentsService (Razorpay orders + webhook).
 */

function makeController() {
  const paymentsService: any = {
    getGatewayStatus: jest.fn(() => ({
      wallet: { available: false },
      cash: { available: true },
      razorpay: {
        available: false,
        needsApiKey: true,
        message: 'm',
      },
      upi: {
        available: false,
        provider: 'PHONEPE',
        needsApiKey: true,
        message: 'm',
      },
    })),
    createRechargeOrder: jest.fn(async () => ({
      orderId: 'order_1',
      amount: 10000,
      currency: 'INR',
      keyId: 'rzp_test',
    })),
    createPeriodFeeOrder: jest.fn(async () => ({
      orderId: 'order_fee',
      amount: 4900,
      currency: 'INR',
      keyId: 'rzp_test',
    })),
    createLateCancelCompensationOrder: jest.fn(async () => ({
      orderId: 'order_lcc',
      amount: 15000,
      currency: 'INR',
      keyId: 'rzp_test',
    })),
    handleWebhook: jest.fn(async () => ({ ok: true })),
  };
  const controller = new PaymentsController(paymentsService);
  return { controller, paymentsService };
}

describe('PaymentsController.getGatewayStatus', () => {
  it('returns the service gateway-status payload verbatim', () => {
    const { controller, paymentsService } = makeController();
    const res = controller.getGatewayStatus();
    expect(paymentsService.getGatewayStatus).toHaveBeenCalledTimes(1);
    expect(res).toEqual(paymentsService.getGatewayStatus.mock.results[0].value);
    expect(res.razorpay.needsApiKey).toBe(true);
  });
});

describe('PaymentsController.createRechargeOrder', () => {
  it('forwards the caller id and amount to the service', async () => {
    const { controller, paymentsService } = makeController();
    const res = await controller.createRechargeOrder(
      { user: { userId: 'u-1' } },
      { amount: 250 },
    );
    expect(paymentsService.createRechargeOrder).toHaveBeenCalledWith('u-1', 250);
    expect(res).toEqual({
      orderId: 'order_1',
      amount: 10000,
      currency: 'INR',
      keyId: 'rzp_test',
    });
  });
});

describe('PaymentsController.createPeriodFeeOrder', () => {
  it('forwards the caller id', async () => {
    const { controller, paymentsService } = makeController();
    await controller.createPeriodFeeOrder({ user: { userId: 'w-1' } });
    expect(paymentsService.createPeriodFeeOrder).toHaveBeenCalledWith('w-1');
  });
});

describe('PaymentsController.createLateCancelCompensationOrder', () => {
  it('forwards the caller id', async () => {
    const { controller, paymentsService } = makeController();
    await controller.createLateCancelCompensationOrder({
      user: { userId: 'c-1' },
    });
    expect(
      paymentsService.createLateCancelCompensationOrder,
    ).toHaveBeenCalledWith('c-1');
  });
});

describe('PaymentsController.webhook', () => {
  it('passes rawBody and signature to the service', async () => {
    const { controller, paymentsService } = makeController();
    const raw = Buffer.from('{"event":"payment.captured"}');
    const res = await controller.webhook(
      { rawBody: raw } as any,
      'sig-abc',
    );
    expect(paymentsService.handleWebhook).toHaveBeenCalledWith(raw, 'sig-abc');
    expect(res).toEqual({ ok: true });
  });
});
