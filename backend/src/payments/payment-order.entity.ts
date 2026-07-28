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
  /** Webhook verified and the wallet was credited. Terminal. */
  CREDITED = 'CREDITED',
  /** Payment failed/expired (currently informational only). */
  FAILED = 'FAILED',
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
