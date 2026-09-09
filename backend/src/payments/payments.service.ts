import {
  Injectable,
  BadRequestException,
  ForbiddenException,
  Logger,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Not, Repository } from 'typeorm';
import * as crypto from 'crypto';
import {
  PaymentOrder,
  PaymentOrderStatus,
  PaymentPurpose,
} from './payment-order.entity';
import { WalletsService } from '../wallets/wallets.service';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { WorkersService } from '../workers/workers.service';
import { BookingsService } from '../bookings/bookings.service';
import { MatchingService } from '../hiring/matching/matching.service';
import { normalizeEmployerSalary } from '../hiring/matching/salary-range';
import { parseEmploymentType } from '../hiring/matching/employment-type';
import {
  WALLET_PAYMENTS_ENABLED,
  WalletPaymentsDisabledError,
} from '../common/money-model';
import { isRealSecret } from '../common/env-secrets';
import { NoticePeriod } from '../hiring/matching/job-preference.entity';
import { JobPackPaymentsService } from '../billing/job-pack-payments.service';

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
    private readonly bookingsService: BookingsService,
    @Inject(forwardRef(() => MatchingService))
    private readonly matchingService: MatchingService,
    private readonly jobPacks: JobPackPaymentsService,
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
    return isRealSecret(this.keyId) && isRealSecret(this.keySecret);
  }

  /**
   * Gateway readiness for the client payment-method picker.
   * See common/money-model.ts — wallet off; jobs settle cash/UPI; Razorpay
   * is for period fee + late-cancel compensation (not wallet recharge).
   */
  getGatewayStatus() {
    return {
      wallet: {
        available: WALLET_PAYMENTS_ENABLED,
        message: WALLET_PAYMENTS_ENABLED
          ? null
          : 'Gixbee Wallet is off — pay the pro directly (cash/UPI).',
      },
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
        message:
          'In-app UPI gateway not configured — use cash/UPI with the pro, or Razorpay for period fee / late-cancel.',
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
    if (!WALLET_PAYMENTS_ENABLED) {
      throw new BadRequestException(
        new WalletPaymentsDisabledError('wallet recharge').message,
      );
    }
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

  /**
   * Customer late-cancel travel compensation — amount is frozen on the user
   * at ban time (distance-based). Fulfilment unlocks Instant Help.
   */
  async createLateCancelCompensationOrder(userId: string): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
  }> {
    const quote =
      await this.bookingsService.getLateCancelCompensationQuote(userId);
    if (!quote.blocked || !quote.amountInr || quote.amountInr <= 0) {
      throw new BadRequestException(
        'No travel compensation is due — Instant Help is not blocked.',
      );
    }
    return this.createOrder(
      userId,
      quote.amountInr,
      PaymentPurpose.LATE_CANCEL_COMPENSATION,
    );
  }

  /**
   * Employer Smart Hiring match fee — amount = fee − hiring credit.
   * Webhook starts the 24 h matching engine.
   */
  async createHiringMatchOrder(
    userId: string,
    body: {
      jobType: string;
      skills?: string[];
      location?: string;
      salaryOffered?: number;
      salaryMin?: number;
      salaryMax?: number;
      salaryNegotiable?: boolean;
      employmentType?: string;
      experienceMinYears?: number;
      vacancies: number;
    },
  ): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
    fee: number;
    creditApplied: number;
    amountDue: number;
  }> {
    const jobType = (body.jobType || '').trim();
    if (!jobType) throw new BadRequestException('jobType is required');
    const salary = normalizeEmployerSalary(body);
    const employmentType = parseEmploymentType(body.employmentType);
    const vacancies = Math.max(1, Math.round(Number(body.vacancies) || 1));
    const quote = await this.matchingService.quoteMatchFee(userId, vacancies);
    if (quote.amountDue <= 0) {
      throw new BadRequestException(
        'No payment due — create the hiring request directly (credit covers the fee).',
      );
    }
    const order = await this.createOrder(
      userId,
      quote.amountDue,
      PaymentPurpose.HIRING_MATCH_FEE,
      {
        jobType,
        skills: body.skills ?? [],
        location: body.location,
        salaryOffered: salary.salaryOffered,
        salaryMin: salary.salaryMin,
        salaryMax: salary.salaryMax,
        salaryNegotiable: salary.salaryNegotiable,
        employmentType,
        experienceMinYears: body.experienceMinYears ?? 0,
        vacancies,
        fee: quote.fee,
        creditApplied: quote.creditApplied,
      },
    );
    return { ...order, ...quote };
  }

  /** Candidate 3rd+ Job Type — ₹50/month. Webhook creates the preference. */
  async createExtraJobTypeOrder(
    userId: string,
    body: {
      jobType: string;
      skills?: string[];
      preferredLocation?: string;
      expectedSalary?: number;
      salaryNegotiable?: boolean;
      employmentType?: string;
      experienceYears?: number;
      noticePeriod?: NoticePeriod;
    },
  ): Promise<{
    orderId: string;
    amount: number;
    currency: string;
    keyId: string;
  }> {
    const jobType = (body.jobType || '').trim();
    if (!jobType) throw new BadRequestException('jobType is required');
    const existing = await this.matchingService.listMyPreferences(userId);
    if (existing.length < 2) {
      throw new BadRequestException(
        'Your first two Job Types are free — create them without payment.',
      );
    }
    if (
      existing.some((p) => p.jobType.toLowerCase() === jobType.toLowerCase())
    ) {
      throw new BadRequestException(
        'You already have a profile for this Job Type',
      );
    }
    return this.createOrder(userId, 50, PaymentPurpose.EXTRA_JOB_TYPE_FEE, {
      jobType,
      skills: body.skills ?? [],
      preferredLocation: body.preferredLocation,
      expectedSalary: body.expectedSalary ?? 0,
      salaryNegotiable: body.salaryNegotiable === true,
      employmentType: parseEmploymentType(body.employmentType),
      experienceYears: body.experienceYears ?? 0,
      noticePeriod: body.noticePeriod ?? NoticePeriod.IMMEDIATE,
    });
  }

  /** Refund a captured hiring-match payment (guarantee REFUND remedy). */
  async refundHiringMatchPayment(
    razorpayPaymentId: string,
    amountRupees: number,
  ): Promise<void> {
    if (!this.razorpayConfigured) {
      throw new BadRequestException(
        'Cannot refund — payment gateway is not configured.',
      );
    }
    const paise = Math.round(Number(amountRupees) * 100);
    if (!(paise > 0)) return;
    const auth = Buffer.from(`${this.keyId}:${this.keySecret}`).toString(
      'base64',
    );
    const res = await fetch(
      `https://api.razorpay.com/v1/payments/${razorpayPaymentId}/refund`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ amount: paise }),
      },
    );
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      this.logger.error(
        `[Razorpay] refund failed (${res.status}): ${detail.slice(0, 500)}`,
      );
      throw new BadRequestException(
        'Refund could not be processed automatically — support will complete it.',
      );
    }
    this.logger.log(
      `[Razorpay] refunded ₹${amountRupees} on payment ${razorpayPaymentId}`,
    );
  }

  private async createOrder(
    userId: string,
    rupees: number,
    purpose: PaymentPurpose,
    meta?: Record<string, unknown>,
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

    const receiptPrefix =
      purpose === PaymentPurpose.PERIOD_FEE
        ? 'fee'
        : purpose === PaymentPurpose.LATE_CANCEL_COMPENSATION
          ? 'lcc'
          : purpose === PaymentPurpose.HIRING_MATCH_FEE
            ? 'hmf'
            : purpose === PaymentPurpose.EXTRA_JOB_TYPE_FEE
              ? 'ejt'
              : 'rcg';

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
        receipt: `${receiptPrefix}_${Date.now().toString(36)}`,
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
        meta: meta ?? null,
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

    // Credit packs commit the order receipt and balance in one transaction.
    if (await this.jobPacks.handleCaptured(payment)) {
      return { ok: true };
    }

    // Atomic idempotent claim.
    const claim = await this.ordersRepo.update(
      {
        razorpayOrderId: orderId,
        status: PaymentOrderStatus.CREATED,
        purpose: Not(PaymentPurpose.JOB_CREDITS),
      },
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

    if (order.purpose === PaymentPurpose.LATE_CANCEL_COMPENSATION) {
      try {
        await this.bookingsService.markLateCancelCompensationPaid(order.userId);
        this.logger.log(
          `[Razorpay] ${orderId}: late-cancel compensation ₹${order.amount} — Instant Help unlocked for ${order.userId}`,
        );
      } catch (e) {
        await this.ordersRepo
          .update(
            { razorpayOrderId: orderId },
            { status: PaymentOrderStatus.CREATED, razorpayPaymentId: null },
          )
          .catch(() => {});
        this.logger.error(
          `[Razorpay] ${orderId}: late-cancel compensation FAILED — claim reverted: ${
            (e as Error)?.message ?? e
          }`,
        );
        throw e;
      }
      return { ok: true };
    }

    if (order.purpose === PaymentPurpose.HIRING_MATCH_FEE) {
      try {
        const meta = (order.meta ?? {}) as Record<string, any>;
        await this.matchingService.createRequestFromPayment(
          order.userId,
          {
            jobType: String(meta.jobType ?? ''),
            skills: Array.isArray(meta.skills) ? meta.skills : [],
            location: meta.location,
            salaryOffered: Number(meta.salaryOffered) || 0,
            salaryMin: Number(meta.salaryMin) || 0,
            salaryMax:
              Number(meta.salaryMax) || Number(meta.salaryOffered) || 0,
            salaryNegotiable: meta.salaryNegotiable === true,
            employmentType: parseEmploymentType(meta.employmentType),
            experienceMinYears: Number(meta.experienceMinYears) || 0,
            vacancies: Number(meta.vacancies) || 1,
          },
          {
            feeAmount: Number(meta.fee) || Number(order.amount),
            creditApplied: Number(meta.creditApplied) || 0,
            paymentOrderId: order.id,
            razorpayPaymentId: order.razorpayPaymentId,
          },
        );
        this.logger.log(
          `[Razorpay] ${orderId}: hiring match fee ₹${order.amount} — request started for ${order.userId}`,
        );
      } catch (e) {
        await this.ordersRepo
          .update(
            { razorpayOrderId: orderId },
            { status: PaymentOrderStatus.CREATED, razorpayPaymentId: null },
          )
          .catch(() => {});
        this.logger.error(
          `[Razorpay] ${orderId}: hiring-match fulfilment FAILED — claim reverted: ${
            (e as Error)?.message ?? e
          }`,
        );
        throw e;
      }
      return { ok: true };
    }

    if (order.purpose === PaymentPurpose.EXTRA_JOB_TYPE_FEE) {
      try {
        const meta = (order.meta ?? {}) as Record<string, any>;
        await this.matchingService.createPreferenceFromPayment(order.userId, {
          jobType: String(meta.jobType ?? ''),
          skills: Array.isArray(meta.skills) ? meta.skills : [],
          preferredLocation: meta.preferredLocation,
          expectedSalary: Number(meta.expectedSalary) || 0,
          salaryNegotiable: meta.salaryNegotiable === true,
          employmentType: parseEmploymentType(meta.employmentType),
          experienceYears: Number(meta.experienceYears) || 0,
          noticePeriod: meta.noticePeriod as NoticePeriod | undefined,
        });
        this.logger.log(
          `[Razorpay] ${orderId}: extra Job Type fee ₹${order.amount} — preference created for ${order.userId}`,
        );
      } catch (e) {
        await this.ordersRepo
          .update(
            { razorpayOrderId: orderId },
            { status: PaymentOrderStatus.CREATED, razorpayPaymentId: null },
          )
          .catch(() => {});
        this.logger.error(
          `[Razorpay] ${orderId}: extra-job-type fulfilment FAILED — claim reverted: ${
            (e as Error)?.message ?? e
          }`,
        );
        throw e;
      }
      return { ok: true };
    }

    // WALLET_RECHARGE: credit the wallet only when the product is on.
    if (!WALLET_PAYMENTS_ENABLED) {
      this.logger.warn(
        `[Razorpay] ${orderId}: wallet recharge ignored — WALLET_PAYMENTS_ENABLED=false`,
      );
      return { ok: true, ignored: 'wallet_disabled' };
    }
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
