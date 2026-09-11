import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn, CreateDateColumn } from 'typeorm';
import { PaymentOrder } from '../../payments/payment-order.entity';
import { JobPreference } from './job-preference.entity';
@Entity('career_profile_receipts')
export class CareerProfileReceipt {
  @PrimaryColumn('uuid') paymentOrderId: string;
  @ManyToOne(() => PaymentOrder, { nullable: false }) @JoinColumn({ name: 'paymentOrderId' }) paymentOrder: PaymentOrder;
  @Column('uuid') preferenceId: string;
  @ManyToOne(() => JobPreference, { nullable: false }) @JoinColumn({ name: 'preferenceId' }) preference: JobPreference;
  @CreateDateColumn({ type: 'timestamptz' }) createdAt: Date;
}
