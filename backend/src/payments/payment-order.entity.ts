import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export enum PaymentOrderStatus {
  /** Razorpay order created; awaiting payment + webhook. */
  CREATED = 'CREATED',
  /** Webhook verified and the purchase was fulfilled. Terminal. */
  CREDITED = 'CREDITED',
  /** Payment failed/expired (currently informational only). */
  FAILED = 'FAILED',
}

export enum PaymentPurpose {
  /** Purchased acceptance credits; entitlement is frozen in meta. */
  JOB_CREDITS = 'JOB_CREDITS',
  /** Customer wallet top-up — fulfilment credits the wallet. */
  WALLET_RECHARGE = 'WALLET_RECHARGE',
  /** Worker periodic platform fee ("N jobs, then pay") — fulfilment
   *  resets jobsSincePayment so the pro can go live again. NO wallet
   *  involvement: the payment_orders row is the receipt. */
  PERIOD_FEE = 'PERIOD_FEE',
  /** Customer late-cancel travel compensation — unlocks Instant Help and
   *  records a payout owed to the affected worker. */
  LATE_CANCEL_COMPENSATION = 'LATE_CANCEL_COMPENSATION',
  /** Employer Smart Hiring match fee (₹49/99/199/399) — webhook creates
   *  the HiringRequest and starts the 24 h matching engine. */
  HIRING_MATCH_FEE = 'HIRING_MATCH_FEE',
  /** Candidate 3rd+ Job Type preference (₹50/month) — webhook creates
   *  the paid JobPreference. */
  EXTRA_JOB_TYPE_FEE = 'EXTRA_JOB_TYPE_FEE',
}

/**
 * Server-side ledger of Razorpay recharge orders.
 *
 * Platform fees are fulfilled by signed webhooks. Credit packs also support
 * an authenticated checkout callback, verified against the provider's captured
 * payment API; their order, balance and credit receipt commit atomically.
 */
@Entity('payment_orders')
export class PaymentOrder {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column({ type: 'uuid' })
  userId: string;

  /** Rupees (what the wallet is credited). Razorpay speaks paise: ×100. */
  @Column({ type: 'decimal', precision: 10, scale: 2 })
  amount: number;

  @Index({ unique: true })
  @Column()
  razorpayOrderId: string;

  @Column({
    type: 'enum',
    enum: PaymentPurpose,
    default: PaymentPurpose.WALLET_RECHARGE,
  })
  purpose: PaymentPurpose;

  @Column({ type: 'varchar', nullable: true })
  razorpayPaymentId: string | null;

  @Column({
    type: 'enum',
    enum: PaymentOrderStatus,
    default: PaymentOrderStatus.CREATED,
  })
  status: PaymentOrderStatus;

  /**
   * Draft payload for webhook fulfilment (hiring match criteria, Job Type
   * preference fields, credit applied, etc.). JSONB so Postgres stores it
   * without a parallel pending table.
   */
  @Column({ type: 'jsonb', nullable: true })
  meta: Record<string, unknown> | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
