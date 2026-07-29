import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, Index } from 'typeorm';
import { User } from '../users/user.entity';

export enum CreditTransactionReason {
  PURCHASE = 'PURCHASE',
  JOB_ACCEPTED = 'JOB_ACCEPTED',
  REFUND_CUSTOMER_CANCEL = 'REFUND_CUSTOMER_CANCEL',
  REFUND_NOSHOW = 'REFUND_NOSHOW',
}

@Entity('credit_transactions')
export class CreditTransaction {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  user: User;

  @Column({ type: 'int' })
  delta: number;

  @Column({
    type: 'enum',
    enum: CreditTransactionReason,
  })
  reason: CreditTransactionReason;

  @Column({ nullable: true })
  bookingId: string;

  @Column({ nullable: true })
  razorpayPaymentId: string;

  @CreateDateColumn()
  createdAt: Date;
}
