import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  Index,
} from 'typeorm';
import { User } from '../../users/user.entity';
import { EmploymentType } from './employment-type';

export enum HiringRequestStatus {
  /** Matching engine is collecting interested candidates (≤ 24 h). */
  COLLECTING = 'COLLECTING',
  /** Target reached (or enough at deadline) — shortlist delivered. */
  DELIVERED = 'DELIVERED',
  /** 24 h passed without the guaranteed minimum — employer chooses remedy. */
  GUARANTEE_FAILED = 'GUARANTEE_FAILED',
  /** Guarantee remedy taken: full fee returned as Gixbee Credit. */
  RESOLVED_CREDIT = 'RESOLVED_CREDIT',
  /** Guarantee remedy taken: refund to original payment method (processed offline). */
  RESOLVED_REFUND = 'RESOLVED_REFUND',
  CLOSED = 'CLOSED',
}

/**
 * An employer's paid Smart Hiring request (FRD: Hire Employee module +
 * 24 Hour Hiring Guarantee doc).
 *
 * Employers pay for MATCHING, not posting: the fee (₹49/99/199/399 by
 * vacancy tier) runs the matching engine for up to 24 hours, notifying
 * matching candidates in batches until ~3× vacancies have tapped
 * "Interested", then the curated list is delivered.
 */
@Entity('hiring_requests')
@Index(['status', 'deadlineAt'])
export class HiringRequest {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  employer: User;

  @Column()
  jobType: string;

  @Column('simple-array', { nullable: true })
  skills: string[];

  @Column({ nullable: true })
  location: string;

  /** Offered salary in ₹ per month (legacy ceiling — mirrors salaryMax). */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  salaryOffered: number;

  /** Employer budget floor (₹/month). 0 when negotiable-only max is set. */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  salaryMin: number;

  /** Employer budget ceiling (₹/month). */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  salaryMax: number;

  /** When true, matcher treats employer min as 0 (flexible below stated range). */
  @Column({ default: false })
  salaryNegotiable: boolean;

  /** FT/PT/Intern/Contract — hard-filter when seeker also declares type (V147-02). */
  @Column({ type: 'enum', enum: EmploymentType, nullable: true })
  employmentType: EmploymentType | null;

  /** Minimum experience required, in years (0 = freshers welcome). */
  @Column({ type: 'int', default: 0 })
  experienceMinYears: number;

  @Column({ type: 'int', default: 1 })
  vacancies: number;

  /** Interested-candidate target (~3× vacancies per the FRD). */
  @Column({ type: 'int', default: 3 })
  targetInterested: number;

  /** Fee charged at creation (₹) — Razorpay and/or hiring credit. */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  feeAmount: number;

  /** Portion covered by hiring credit at creation (₹). */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  creditApplied: number;

  /** payment_orders.id when paid via Razorpay (for guarantee refunds). */
  @Column({ type: 'uuid', nullable: true })
  paymentOrderId: string | null;

  /** Razorpay payment id captured on the order (refund target). */
  @Column({ type: 'varchar', nullable: true })
  razorpayPaymentId: string | null;

  @Column({
    type: 'enum',
    enum: HiringRequestStatus,
    default: HiringRequestStatus.COLLECTING,
  })
  status: HiringRequestStatus;

  /** createdAt + 24 h — the guarantee window. */
  @Column({ type: 'timestamptz' })
  deadlineAt: Date;

  @Column({ type: 'int', default: 0 })
  batchesSent: number;

  @Column({ type: 'timestamptz', nullable: true })
  deliveredAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  resolvedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
