import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn,
  ManyToOne, JoinColumn, Index, Unique, Check } from 'typeorm';
import { EventPlan } from './event-plan.entity';
import { Business } from '../businesses/business.entity';
import { User } from '../users/user.entity';

@Entity('event_quotes')
@Unique(['planId', 'businessId', 'serviceType', 'revision'])
@Index('event_quotes_selected_service', ['planId', 'serviceType'], {
  unique: true, where: "status IN ('CONFIRMED','COMPLETED','CANCEL_REQUESTED')",
})
@Index('event_quotes_business', ['businessId', 'status'])
@Check('amount > 0')
@Check('"cancellationRefund" >= 0')
@Check('"cancellationRefund" <= amount')
@Check("status IN ('OFFERED','DECLINED','EXPIRED','CONFIRMED','COMPLETED','CANCEL_REQUESTED','CANCELLED','SUPERSEDED')")
export class EventQuote {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column('uuid') planId: string;
  @ManyToOne(() => EventPlan, { nullable: false }) @JoinColumn({ name: 'planId' }) plan: EventPlan;
  @Column('uuid') businessId: string;
  @ManyToOne(() => Business, { nullable: false }) @JoinColumn({ name: 'businessId' }) business: Business;
  @Column({ type: 'varchar', length: 40 }) serviceType: string;
  /** Monotonic offer generation per plan+business+serviceType. */
  @Column({ type: 'int', default: 1 }) revision: number;
  @Column({ type: 'uuid', nullable: true }) supersedesQuoteId: string | null;
  @Column({ type: 'uuid', nullable: true }) hallEnquiryId: string | null;
  @Column({ type: 'uuid', nullable: true }) hallId: string | null;
  @Column({ type: 'timestamptz', nullable: true }) intervalStart: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) intervalEnd: Date | null;
  @Column({ type: 'varchar', length: 40, nullable: true }) supersedeReason: string | null;
  @Column({ type: 'numeric', precision: 12, scale: 2 }) amount: string;
  @Column('text') inclusions: string;
  @Column('text') cancellationTerms: string;
  @Column({ type: 'varchar', length: 30, default: 'OFFERED' }) status: string;
  @Column('timestamptz') expiresAt: Date;
  @Column({ type: 'timestamptz', nullable: true }) acceptedAt: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) customerPaidAt: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) vendorReceivedAt: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) customerCompletedAt: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) vendorCompletedAt: Date | null;
  @Column({ type: 'uuid', nullable: true }) cancellationRequestedBy: string | null;
  @ManyToOne(() => User, { nullable: true }) @JoinColumn({ name: 'cancellationRequestedBy' }) cancellationRequester: User | null;
  @Column({ type: 'text', nullable: true }) cancellationReason: string | null;
  @Column({ type: 'numeric', precision: 12, scale: 2, default: 0 }) cancellationRefund: string;
  @Column({ type: 'timestamptz', nullable: true }) customerRefundReceivedAt: Date | null;
  @Column({ type: 'timestamptz', nullable: true }) vendorRefundSentAt: Date | null;
  @CreateDateColumn({ type: 'timestamptz' }) createdAt: Date;
  @UpdateDateColumn({ type: 'timestamptz' }) updatedAt: Date;
}
