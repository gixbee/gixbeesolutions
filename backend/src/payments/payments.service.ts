import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as crypto from 'crypto';
import {
  PaymentOrder,
  PaymentOrderStatus,
  PaymentPurpose,
} from './payment-order.entity';
import { WalletsService } from '../wallets/wallets.service';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { WorkersService } from '../workers/workers.service';

/**
 * Razorpay wallet-recharge integration.
 *
 * Flow:
 *  1. App: POST /payments/recharge/order {amount} → we create a Razorpay
 *     Order (server-side, REST API with key secret — no SDK dependency) and
 *     persist a PaymentOrder row (CREATED).
 *  2. App opens Razorpay Checkout with that order_id.
 *  3. Razorpay calls POST /payments/webhook (payment.captured). We verify
 *     the HMAC signature against the RAW body, atomically claim the order
 *     (CREATED → CREDITED — duplicate deliveries and the parallel
 *     order.paid event lose the claim and are ignored), then credit the
 *     wallet. First credited recharge can add a bonus
 *     (Master Entries → first_recharge_bonus, ₹, 0 = off).
 *
 * The client's payment-success callback NEVER credits — webhook-only, so a
 * modified client cannot mint balance.
 */
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger(PaymentsService.name);

  constructor(
    private readonly config: ConfigService,
    @InjectRepository(PaymentOrder)
    private readonly ordersRepo: Repository<PaymentOrder>,
    private readonly walletsService: WalletsService,
    private readonly masterEntriesService: MasterEntriesService,
    private readonly workersService: WorkersService,
  ) {}

  private get keyId(): string {
    return this.config.get<string>('RAZORPAY_KEY_ID') ?? '';
  }
  private get keySecret(): string {
    return this.config.get<string>('RAZORPAY_KEY_SECRET') ?? '';
  }
  private get webhookSecret(): string {
    return this.config.get<string>('RAZORPAY_WEBHOOK_SECRET') ?? '';
  }
  private get razorpayConfigured(): boolean {
    return Boolean(this.keyId && this.keySecret);
  }

  /**
   * Gateway readiness for the client payment-method picker. Razorpay drives
   * wallet recharge; wallet/cash remain the booking settlement methods.
   */
  getGatewayStatus() {
    return {
      // WALLET IS OFF (product decision): no customer/worker wallet for
      // now — jobs settle directly (cash/UPI dual-confirm). Kept in the
      // payload so older app builds' pickers render it as unavailable
      // instead of crashing on a missing key.
      wallet: { available: false },
      cash: { available: true },
      razorpay: {
        available: this.razorpayConfigured,
        needsApiKey: !this.razorpayConfigured,
        message: this.razorpayConfigured
          ? null
          : 'Razorpay not configured — set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET',
      },
      // Legacy field kept so older app builds' pickers don't break.
      upi: {
        available: false,
        provider: 'PHONEPE',
        needsApiKey: true,
        message: 'Direct UPI gateway not configured — use wallet recharge.',
      },
    };
  }

  /**
   * Create a Razorpay Order for a wallet recharge and persist the ledger
   * row. Returns exactly what Checkout needs; the amount is echoed in PAISE
   * because that is Razorpay's unit.
   */
  async createRechargeOrder(
    userId: string,
    amount: number,
  ): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
  }> {
    const rupees = Math.round(Number(amount));
    if (!Number.isFinite(rupees) || rupees < 10 || rupees > 100000) {
      throw new BadRequestException(
        'Recharge amount must be between ₹10 and ₹1,00,000.',
      );
    }
    return this.createOrder(userId, rupees, PaymentPurpose.WALLET_RECHARGE);
  }

  /**
   * Worker period-fee checkout ("N jobs, then pay") — DIRECT payment, no
   * wallet hop. The PRICE COMES FROM THE SERVER (Master Entries →
   * go_live_period_fee); the client only asks for the order. Fulfilment on
   * webhook: WorkersService.markPeriodFeePaid resets the job counter.
   */
  async createPeriodFeeOrder(userId: string): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
  }> {
    const jobsIncluded = await this.workersService.periodicJobsPerPayment();
    if (jobsIncluded <= 0) {
      throw new BadRequestException(
        'The per-jobs payment plan is not enabled.',
      );
    }
    const fee = await this.masterEntriesService.getConfigNumber(
      'go_live_period_fee',
      49,
    );
    if (fee <= 0) {
      throw new BadRequestException('No fee is configured for the plan.');
    }
    return this.createOrder(userId, fee, PaymentPurpose.PERIOD_FEE);
  }

  private async createOrder(
    userId: string,
    rupees: number,
    purpose: PaymentPurpose,
  ): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
  }> {
    if (!this.razorpayConfigured) {
      throw new BadRequestException(
        'Online payment is not available yet — payment gateway is not configured on the server.',
      );
    }

    const auth = Buffer.from(`${this.keyId}:${this.keySecret}`).toString(
      'base64',
    );
    const res = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: rupees * 100, // paise
        currency: 'INR',
        receipt: `${purpose === PaymentPurpose.PERIOD_FEE ? 'fee' : 'rcg'}_${Date.now().toString(36)}`,
        notes: { gixbeeUserId: userId, purpose },
      }),
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      this.logger.error(
        `[Razorpay] order create failed (${res.status}): ${detail.slice(0, 500)}`,
      );
      throw new BadRequestException(
        'Could not start the payment — please try again in a moment.',
      );
    }

    const order = (await res.json()) as { id: string };
    await this.ordersRepo.save(
      this.ordersRepo.create({
        userId,
        amount: rupees,
        razorpayOrderId: order.id,
        purpose,
        status: PaymentOrderStatus.CREATED,
      }),
    );

    this.logger.log(
      `[Razorpay] order ${order.id} created — ₹${rupees} ${purpose} for ${userId}`,
    );
    return {
      orderId: order.id,
      amount: rupees * 100,
      currency: 'INR',
      keyId: this.keyId,
    };
  }

  /** Constant-time HMAC-SHA256 check against the RAW request body. */
  private verifyWebhookSignature(rawBody: Buffer, signature: string): boolean {
    if (!this.webhookSecret || !signature) return false;
    const expected = crypto
      .createHmac('sha256', this.webhookSecret)
      .update(rawBody)
      .digest('hex');
    try {
      return crypto.timingSafeEqual(
        Buffer.from(expected),
        Buffer.from(signature),
      );
    } catch {
      return false;
    }
  }

  /**
   * Razorpay webhook — the ONLY place wallet credit happens.
   *
   * Idempotency: the CREATED → CREDITED transition is a single conditional
   * UPDATE; whichever delivery wins credits, every other delivery
   * (retries, the parallel order.paid event) affects 0 rows and is ignored.
   * If the wallet credit itself fails after a successful claim, the claim
   * is reverted and we throw — Razorpay retries the webhook and the credit
   * is attempted again.
   */
  async handleWebhook(
    rawBody: Buffer | undefined,
    signature: string | undefined,
  ): Promise<{ ok: boolean; duplicate?: boolean; ignored?: string }> {
    if (!rawBody || rawBody.length === 0) {
      throw new BadRequestException('Missing request body');
    }
    if (!this.verifyWebhookSignature(rawBody, signature ?? '')) {
      this.logger.warn('[Razorpay] webhook signature mismatch — rejected');
      throw new ForbiddenException('Invalid signature');
    }

    let event: any;
    try {
      event = JSON.parse(rawBody.toString('utf8'));
    } catch {
      throw new BadRequestException('Invalid JSON');
    }

    const type = String(event?.event ?? '');
    if (type !== 'payment.captured' && type !== 'order.paid') {
      return { ok: true, ignored: type };
    }

    const payment = event?.payload?.payment?.entity;
    const orderId: string | undefined =
      payment?.order_id ?? event?.payload?.order?.entity?.id;
    const paymentId: string | null = payment?.id ?? null;
    if (!orderId) return { ok: true, ignored: 'no order id' };

    // Atomic idempotent claim.
    const claim = await this.ordersRepo.update(
      { razorpayOrderId: orderId, status: PaymentOrderStatus.CREATED },
      { status: PaymentOrderStatus.CREDITED, razorpayPaymentId: paymentId },
    );
    if (!claim.affected) {
      this.logger.log(
        `[Razorpay] ${orderId}: already credited or unknown — duplicate delivery ignored`,
      );
      return { ok: true, duplicate: true };
    }

    const order = await this.ordersRepo.findOne({
      where: { razorpayOrderId: orderId },
    });
    if (!order) return { ok: true }; // unreachable after a successful claim

    // ── Fulfilment by purpose ──
    if (order.purpose === PaymentPurpose.PERIOD_FEE) {
      // Worker platform fee: unlock the next batch of included jobs.
      // Direct payment — the wallet is never touched.
      try {
        await this.workersService.markPeriodFeePaid(order.userId);
        this.logger.log(
          `[Razorpay] ${orderId}: period fee ₹${order.amount} — jobs unlocked for ${order.userId}`,
        );
      } catch (e) {
        await this.ordersRepo
          .update(
            { razorpayOrderId: orderId },
            { status: PaymentOrderStatus.CREATED, razorpayPaymentId: null },
          )
          .catch(() => {});
        this.logger.error(
          `[Razorpay] ${orderId}: period-fee fulfilment FAILED — claim reverted for retry: ${
            (e as Error)?.message ?? e
          }`,
        );
        throw e; // 5xx → Razorpay retries the webhook
      }
      return { ok: true };
    }

    // WALLET_RECHARGE (default): credit the wallet.
    try {
      await this.walletsService.addFunds(
        order.userId,
        Number(order.amount),
        'Wallet Recharge (Razorpay)',
      );
      this.logger.log(
        `[Razorpay] ${orderId}: credited ₹${order.amount} to ${order.userId}`,
      );
    } catch (e) {
      // Revert the claim so Razorpay's retry can credit again.
      await this.ordersRepo
        .update(
          { razorpayOrderId: orderId },
          { status: PaymentOrderStatus.CREATED, razorpayPaymentId: null },
        )
        .catch(() => {});
      this.logger.error(
        `[Razorpay] ${orderId}: wallet credit FAILED — claim reverted for retry: ${
          (e as Error)?.message ?? e
        }`,
      );
      throw e; // 5xx → Razorpay retries the webhook
    }

    // First-recharge bonus (Master Entries → first_recharge_bonus, ₹, 0=off).
    try {
      const creditedCount = await this.ordersRepo.count({
        where: {
          userId: order.userId,
          status: PaymentOrderStatus.CREDITED,
          purpose: PaymentPurpose.WALLET_RECHARGE,
        },
      });
      if (creditedCount === 1) {
        const bonus = await this.masterEntriesService.getConfigNumber(
          'first_recharge_bonus',
          0,
        );
        if (bonus > 0) {
          await this.walletsService.addFunds(
            order.userId,
            bonus,
            'First recharge bonus',
          );
          this.logger.log(
            `[Razorpay] first-recharge bonus ₹${bonus} → ${order.userId}`,
          );
        }
      }
    } catch (e) {
      // Bonus is best-effort — never fail the webhook over it.
      this.logger.warn(
        `[Razorpay] first-recharge bonus failed: ${(e as Error)?.message ?? e}`,
      );
    }

    return { ok: true };
  }
}
