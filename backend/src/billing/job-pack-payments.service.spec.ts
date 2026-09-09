import {
  BadRequestException,
  ForbiddenException,
  ServiceUnavailableException,
} from '@nestjs/common';
import * as crypto from 'crypto';
import { JobCreditsService } from './job-credits.service';
import {
  JobPackPaymentsService,
  assertCapturedPackPayment,
} from './job-pack-payments.service';
import {
  PaymentOrder,
  PaymentOrderStatus,
  PaymentPurpose,
} from '../payments/payment-order.entity';
import { JobCredit } from './job-credit.entity';
import { CreditTransaction } from './credit-transaction.entity';
import { User } from '../users/user.entity';
import { PaymentsService } from '../payments/payments.service';

const payment = {
  id: 'pay_test',
  order_id: 'order_test',
  amount: 4900,
  currency: 'INR',
  status: 'captured',
};
function fixture() {
  const order = {
    id: 'order-db',
    userId: 'worker-1',
    razorpayOrderId: 'order_test',
    purpose: PaymentPurpose.JOB_CREDITS,
    status: PaymentOrderStatus.CREATED,
    amount: 49,
    meta: { credits: 45, creditsPerAccept: 15 },
    razorpayPaymentId: null,
  } as PaymentOrder;
  const credit = { balance: 30 };
  const qb: any = {
    where: jest.fn(() => qb),
    setLock: jest.fn(() => qb),
    getOne: jest.fn(async () => credit),
  };
  const orders = {
    findOne: jest.fn(async () => order),
    save: jest.fn(async (value) => value),
  };
  const balances = {
    createQueryBuilder: () => qb,
    create: (value: any) => value,
    save: jest.fn(async (value) => value),
  };
  const receipts = { save: jest.fn(async (value) => value) };
  const users = { findOne: jest.fn(async () => ({ id: 'worker-1' })) };
  const manager = {
    getRepository: (entity: any) => {
      if (entity === PaymentOrder) return orders;
      if (entity === JobCredit) return balances;
      if (entity === CreditTransaction) return receipts;
      if (entity === User) return users;
      throw new Error('Unexpected repository');
    },
  };
  const db: any = {
    ...manager,
    transaction: jest.fn(async (cb) => cb(manager)),
  };
  const config: any = {
    get: (key: string) =>
      ({
        RAZORPAY_KEY_ID: 'rzp_test_example',
        RAZORPAY_KEY_SECRET: 'test-secret',
      })[key],
  };
  const credits: any = {
    getPackInfo: jest.fn(async () => ({
      credits: 45,
      jobs: 3,
      creditsPerAccept: 15,
      price: 49,
    })),
  };
  return {
    service: new JobPackPaymentsService(db, config, credits),
    order,
    credit,
    orders,
    balances,
    receipts,
    db,
    users,
    credits,
  };
}

describe('credit-pack commercial contract', () => {
  it('prices three accepts using the configured debit, including free acceptance', async () => {
    const config: any = { getConfigNumber: jest.fn(async () => 15) };
    const credits = new JobCreditsService(
      {} as any,
      {} as any,
      {} as any,
      config,
    );
    expect(await credits.getPackInfo()).toEqual({
      credits: 45,
      jobs: 3,
      creditsPerAccept: 15,
      price: 49,
      currency: 'INR',
    });
    config.getConfigNumber.mockResolvedValue(7);
    expect((await credits.getPackInfo()).credits).toBe(21);
    config.getConfigNumber.mockResolvedValue(0);
    expect((await credits.getPackInfo()).credits).toBe(0);
  });
});

describe('captured payment validation', () => {
  it('accepts a captured INR payment for the stored order', () => {
    expect(() =>
      assertCapturedPackPayment(payment, fixture().order),
    ).not.toThrow();
  });
  it.each([
    { amount: 1 },
    { currency: 'USD' },
    { status: 'authorized' },
    { order_id: 'order_another' },
    { id: '' },
  ])('rejects mismatched or incomplete payment: %j', (changed) => {
    expect(() =>
      assertCapturedPackPayment({ ...payment, ...changed }, fixture().order),
    ).toThrow(BadRequestException);
  });
});

describe('credit pack receipt', () => {
  it('fulfills the purchased snapshot once across callback/webhook retries', async () => {
    const { service, credit, order, receipts, orders, db } = fixture();
    expect(await service.fulfil(payment, 'worker-1')).toEqual({ balance: 75 });
    expect(await service.fulfil(payment)).toEqual({ balance: 75 });
    expect(credit.balance).toBe(75);
    expect(order.status).toBe(PaymentOrderStatus.CREDITED);
    expect(order.razorpayPaymentId).toBe('pay_test');
    expect(receipts.save).toHaveBeenCalledTimes(1);
    expect(receipts.save).toHaveBeenCalledWith(
      expect.objectContaining({ delta: 45, razorpayPaymentId: 'pay_test' }),
    );
    expect(orders.findOne).toHaveBeenCalledWith(
      expect.objectContaining({ lock: { mode: 'pessimistic_write' } }),
    );
    expect(db.transaction).toHaveBeenCalledTimes(2);
  });
  it('rejects an account mismatch before any balance change', async () => {
    const { service, credit, receipts } = fixture();
    await expect(service.fulfil(payment, 'other-worker')).rejects.toThrow(
      ForbiddenException,
    );
    expect(credit.balance).toBe(30);
    expect(receipts.save).not.toHaveBeenCalled();
  });
  it('rejects a corrupt entitlement and leaves the order unfulfilled', async () => {
    const { service, order, balances } = fixture();
    order.meta = { credits: -45 };
    await expect(service.fulfil(payment)).rejects.toThrow('entitlement');
    expect(order.status).toBe(PaymentOrderStatus.CREATED);
    expect(balances.save).not.toHaveBeenCalled();
  });
  it('does not mark the order credited when the credit receipt fails', async () => {
    const { service, receipts, orders, order } = fixture();
    receipts.save.mockRejectedValue(new Error('write failed'));
    await expect(service.fulfil(payment)).rejects.toThrow('write failed');
    expect(orders.save).not.toHaveBeenCalled();
    expect(order.status).toBe(PaymentOrderStatus.CREATED);
    // A real DataSource rolls back the preceding balance save with this error.
  });

  it('ignores an event with no captured payment entity', async () => {
    const { service, receipts } = fixture();
    expect(await service.handleCaptured(undefined)).toBe(false);
    expect(receipts.save).not.toHaveBeenCalled();
  });

  it('asks Razorpay to retry when a pack order is not persisted yet', async () => {
    const { service, orders, receipts } = fixture();
    orders.findOne.mockResolvedValueOnce(null);
    await expect(
      service.handleCaptured({
        ...payment,
        notes: { purpose: 'JOB_CREDITS' },
      }),
    ).rejects.toThrow(ServiceUnavailableException);
    expect(receipts.save).not.toHaveBeenCalled();
  });
});

describe('Razorpay checkout verification', () => {
  afterEach(() => jest.restoreAllMocks());
  const signed = () => ({
    razorpay_order_id: 'order_test',
    razorpay_payment_id: 'pay_test',
    razorpay_signature: crypto
      .createHmac('sha256', 'test-secret')
      .update('order_test|pay_test')
      .digest('hex'),
  });

  it('checks ownership before contacting the payment provider', async () => {
    const { service } = fixture();
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(service.verify('another', signed())).rejects.toThrow(
      ForbiddenException,
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });
  it('rejects a forged signature without crediting', async () => {
    const { service, receipts } = fixture();
    await expect(
      service.verify('worker-1', {
        ...signed(),
        razorpay_signature: '0'.repeat(64),
      }),
    ).rejects.toThrow('signature');
    expect(receipts.save).not.toHaveBeenCalled();
  });
  it('requires actual capture even when the checkout signature is valid', async () => {
    const { service, receipts } = fixture();
    jest
      .spyOn(global, 'fetch')
      .mockResolvedValue(
        new Response(JSON.stringify({ ...payment, status: 'authorized' })),
      );
    await expect(service.verify('worker-1', signed())).rejects.toThrow(
      'not captured',
    );
    expect(receipts.save).not.toHaveBeenCalled();
  });
  it('fulfills a captured payment after verifying through the provider API', async () => {
    const { service } = fixture();
    const fetchMock = jest
      .spyOn(global, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify(payment)));
    expect(await service.verify('worker-1', signed())).toEqual({ balance: 75 });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.razorpay.com/v1/payments/pay_test',
      expect.anything(),
    );
  });
  it('persists entitlement before returning the real checkout order', async () => {
    const { service, orders } = fixture();
    jest
      .spyOn(global, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({ id: 'order_created' })));
    const result = await service.createOrder('worker-1');
    expect(result).toEqual(
      expect.objectContaining({
        orderId: 'order_created',
        amount: 4900,
        credits: 45,
      }),
    );
    expect(orders.save).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 'worker-1',
        meta: { credits: 45, creditsPerAccept: 15, jobs: 3 },
      }),
    );
  });
  it('does not sell credits while accepts are free', async () => {
    const { service, credits } = fixture();
    credits.getPackInfo.mockResolvedValue({ creditsPerAccept: 0, credits: 0 });
    const fetchMock = jest.spyOn(global, 'fetch');
    await expect(service.createOrder('worker-1')).rejects.toThrow(
      'currently free',
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('credit pack webhook wiring', () => {
  it('fulfills through the atomic credit path after raw signature verification', async () => {
    const { service, credit, orders } = fixture();
    const config: any = { get: () => 'webhook-secret' };
    const gateway = new PaymentsService(
      config,
      orders as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      service,
    );
    const raw = Buffer.from(
      JSON.stringify({
        event: 'payment.captured',
        payload: { payment: { entity: payment } },
      }),
    );
    const signature = crypto
      .createHmac('sha256', 'webhook-secret')
      .update(raw)
      .digest('hex');
    expect(await gateway.handleWebhook(raw, signature)).toEqual({ ok: true });
    expect(credit.balance).toBe(75);
  });

  it('rejects a forged webhook before credit fulfillment', async () => {
    const { service, credit, orders } = fixture();
    const config: any = { get: () => 'webhook-secret' };
    const gateway = new PaymentsService(
      config,
      orders as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      {} as any,
      service,
    );
    const raw = Buffer.from(
      JSON.stringify({
        event: 'payment.captured',
        payload: { payment: { entity: payment } },
      }),
    );
    await expect(gateway.handleWebhook(raw, '0'.repeat(64))).rejects.toThrow();
    expect(credit.balance).toBe(30);
  });
});
