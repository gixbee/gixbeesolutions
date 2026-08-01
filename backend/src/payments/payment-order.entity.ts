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
  /** Customer wallet top-up — fulfilment credits the wallet. */
  WALLET_RECHARGE = 'WALLET_RECHARGE',
  /** Worker periodic platform fee ("N jobs, then pay") — fulfilment
   *  resets jobsSincePayment so the pro can go live again. NO wallet
   *  involvement: the payment_orders row is the receipt. */
  PERIOD_FEE = 'PERIOD_FEE',
  /** Customer late-cancel travel compensation — unlocks Instant Help and
   *  records a payout owed to the affected worker. */
  LATE_CANCEL_COMPENSATION = 'LATE_CANCEL_COMPENSATION',
}

/**
 * Server-side ledger of Razorpay recharge orders.
 *
 * WEBHOOK-ONLY CREDITING: the app's payment-success callback never credits
 * anything — only the signature-verified Razorpay webhook flips
 * CREATED → CREDITED (atomic claim in PaymentsService.handleWebhook), which
 * makes duplicate webhook deliveries and client-side spoofing harmless.
 */
@Entity('payment_orders')
export class PaymentOrder {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @Column()
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

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
