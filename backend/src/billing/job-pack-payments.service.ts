import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import * as crypto from 'crypto';
import { isRealSecret } from '../common/env-secrets';
import {
  PaymentOrder,
  PaymentOrderStatus,
  PaymentPurpose,
} from '../payments/payment-order.entity';
import { User } from '../users/user.entity';
import { JobCredit } from './job-credit.entity';
import {
  CreditTransaction,
  CreditTransactionReason,
} from './credit-transaction.entity';
import { JobCreditsService } from './job-credits.service';

export function assertCapturedPackPayment(
  payment: any,
  order: PaymentOrder,
): void {
  if (
    typeof payment?.id !== 'string' ||
    !payment.id ||
    payment.order_id !== order.razorpayOrderId ||
    payment.status !== 'captured' ||
    payment.currency !== 'INR' ||
    payment.amount !== Math.round(Number(order.amount) * 100)
  ) {
    throw new BadRequestException(
      'Payment is not captured for this order and amount.',
    );
  }
}

/** Both a verified checkout callback and a signed webhook use the same atomic receipt. */
@Injectable()
export class JobPackPaymentsService {
  constructor(
    private readonly db: DataSource,
    private readonly config: ConfigService,
    private readonly credits: JobCreditsService,
  ) {}

  private credentials() {
    const keyId = this.config.get<string>('RAZORPAY_KEY_ID');
    const secret = this.config.get<string>('RAZORPAY_KEY_SECRET');
    if (!isRealSecret(keyId) || !isRealSecret(secret)) {
      throw new BadRequestException('Payment gateway is not configured.');
    }
    return {
      keyId: keyId!,
      secret: secret!,
      auth: Buffer.from(`${keyId}:${secret}`).toString('base64'),
    };
  }

  async createOrder(userId: string) {
    const { keyId, auth } = this.credentials();
    const pack = await this.credits.getPackInfo();
    if (pack.creditsPerAccept === 0) {
      throw new BadRequestException(
        'Job acceptance is currently free; no credit purchase is needed.',
      );
    }
    if (!Number.isSafeInteger(pack.credits) || pack.credits > 2147483647) {
      throw new BadRequestException(
        'The configured credit pack is not available.',
      );
    }
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(15000),
      body: JSON.stringify({
        amount: pack.price * 100,
        currency: 'INR',
        receipt: `pack_${crypto.randomUUID().replace(/-/g, '')}`,
        notes: { gixbeeUserId: userId, purpose: PaymentPurpose.JOB_CREDITS },
      }),
    });
    if (!response.ok)
      throw new BadRequestException('Could not create payment order.');
    const remote = (await response.json()) as { id?: string };
    if (!remote.id)
      throw new BadRequestException('Payment provider returned no order.');
    await this.db.getRepository(PaymentOrder).save({
      userId,
      razorpayOrderId: remote.id,
      purpose: PaymentPurpose.JOB_CREDITS,
      amount: pack.price,
      status: PaymentOrderStatus.CREATED,
      meta: {
        credits: pack.credits,
        creditsPerAccept: pack.creditsPerAccept,
        jobs: pack.jobs,
      },
    });
    return {
      orderId: remote.id,
      amount: pack.price * 100,
      currency: 'INR',
      keyId,
      credits: pack.credits,
    };
  }

  async verify(userId: string, body: Record<string, unknown>) {
    const { secret, auth } = this.credentials();
    const orderId = body?.razorpay_order_id;
    const paymentId = body?.razorpay_payment_id;
    const signature = body?.razorpay_signature;
    if (
      typeof orderId !== 'string' ||
      typeof paymentId !== 'string' ||
      typeof signature !== 'string' ||
      !/^pay_[a-zA-Z0-9]+$/.test(paymentId) ||
      !/^[a-fA-F0-9]{64}$/.test(signature)
    ) {
      throw new BadRequestException(
        'Missing or invalid payment verification details.',
      );
    }
    const order = await this.db
      .getRepository(PaymentOrder)
      .findOne({ where: { razorpayOrderId: orderId } });
    if (
      !order ||
      order.userId !== userId ||
      order.purpose !== PaymentPurpose.JOB_CREDITS
    ) {
      throw new ForbiddenException('This credit order does not belong to you.');
    }
    const expected = crypto
      .createHmac('sha256', secret)
      .update(`${order.razorpayOrderId}|${paymentId}`)
      .digest();
    if (!crypto.timingSafeEqual(expected, Buffer.from(signature, 'hex'))) {
      throw new BadRequestException('Invalid payment signature.');
    }
    const response = await fetch(
      `https://api.razorpay.com/v1/payments/${paymentId}`,
      {
        headers: { Authorization: `Basic ${auth}` },
        signal: AbortSignal.timeout(15000),
      },
    );
    if (!response.ok)
      throw new BadRequestException(
        'Could not verify payment. Refresh credits after payment confirmation.',
      );
    const payment = (await response.json()) as any;
    if (payment?.id !== paymentId)
      throw new BadRequestException('Payment reference did not match.');
    return this.fulfil(payment, userId);
  }

  /** Called only after PaymentsService has verified the raw webhook signature. */
  async handleCaptured(payment: any): Promise<boolean> {
    if (typeof payment?.order_id !== 'string') return false;
    const order = await this.db.getRepository(PaymentOrder).findOne({
      where: {
        razorpayOrderId: payment.order_id,
        purpose: PaymentPurpose.JOB_CREDITS,
      },
    });
    if (!order) {
      // Razorpay can fire payment.captured before our INSERT commits.
      // 503 asks them to retry instead of acknowledging a lost credit pack.
      if (String(payment?.notes?.purpose ?? '') === PaymentPurpose.JOB_CREDITS) {
        throw new ServiceUnavailableException(
          'Credit pack order is not persisted yet',
        );
      }
      return false;
    }
    await this.fulfil(payment);
    return true;
  }

  async fulfil(
    payment: any,
    expectedUserId?: string,
  ): Promise<{ balance: number }> {
    return this.db.transaction(async (manager) => {
      const orders = manager.getRepository(PaymentOrder);
      const order = await orders.findOne({
        where: {
          razorpayOrderId: payment?.order_id,
          purpose: PaymentPurpose.JOB_CREDITS,
        },
        lock: { mode: 'pessimistic_write' },
      });
      if (!order || (expectedUserId && order.userId !== expectedUserId)) {
        throw new ForbiddenException(
          'Credit order not found for this account.',
        );
      }
      assertCapturedPackPayment(payment, order);
      const count = order.meta?.credits;
      if (
        typeof count !== 'number' ||
        !Number.isSafeInteger(count) ||
        count <= 0
      ) {
        throw new BadRequestException(
          'Order has no valid credit entitlement. Contact support.',
        );
      }
      // Serialize creation of a first balance as well as concurrent pack purchases.
      await manager
        .getRepository(User)
        .findOne({
          where: { id: order.userId },
          lock: { mode: 'pessimistic_write' },
        });
      const balances = manager.getRepository(JobCredit);
      let credit = await balances
        .createQueryBuilder('credit')
        .where('credit.userId = :userId', { userId: order.userId })
        .setLock('pessimistic_write')
        .getOne();
      if (order.status === PaymentOrderStatus.CREDITED)
        return { balance: credit?.balance ?? 0 };
      if (order.status !== PaymentOrderStatus.CREATED)
        throw new BadRequestException('Credit order cannot be fulfilled.');
      credit ??= balances.create({ user: { id: order.userId }, balance: 0 });
      credit.balance += count;
      await balances.save(credit);
      await manager.getRepository(CreditTransaction).save({
        user: { id: order.userId },
        delta: count,
        reason: CreditTransactionReason.PURCHASE,
        razorpayPaymentId: payment.id,
      });
      order.razorpayPaymentId = payment.id;
      order.status = PaymentOrderStatus.CREDITED;
      await orders.save(order);
      return { balance: credit.balance };
    });
  }
}
