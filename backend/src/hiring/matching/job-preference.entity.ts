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

/** Indian-standard notice periods for the Smart Hiring matcher. */
export enum NoticePeriod {
  IMMEDIATE = 'IMMEDIATE',
  DAYS_15 = 'DAYS_15',
  DAYS_30 = 'DAYS_30',
  DAYS_60 = 'DAYS_60',
  DAYS_90 = 'DAYS_90',
}

/**
 * A candidate's "Job Type" preference profile (FRD: Find a Job module).
 *
 * Business rules (enforced in MatchingService):
 * - First 2 active preferences are free; each additional one costs
 *   ₹50/month (wallet-charged, `isPaid` + `paidUntil`).
 * - `jobType` is IMMUTABLE after creation — only the other fields can be
 *   edited (quality protection from the FRD).
 * - Deletable only after 7 days (soft delete via `isActive`), preventing
 *   rapid switching just to farm notifications.
 */
@Entity('job_preferences')
@Index(['jobType', 'isActive'])
export class JobPreference {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  user: User;

  /** e.g. 'Backend Engineer', 'Cashier', 'Delivery Executive'. Immutable. */
  @Column()
  jobType: string;

  @Column('simple-array', { nullable: true })
  skills: string[];

  /** Free-text city/area, e.g. 'Kochi', 'Thiruvananthapuram'. */
  @Column({ nullable: true })
  preferredLocation: string;

  /** Expected salary in ₹ per month. */
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  expectedSalary: number;

  /** Total relevant experience in years (0 = fresher). */
  @Column({ type: 'int', default: 0 })
  experienceYears: number;

  @Column({ type: 'enum', enum: NoticePeriod, default: NoticePeriod.IMMEDIATE })
  noticePeriod: NoticePeriod;

  @Column({ default: true })
  isActive: boolean;

  /** True for the 3rd+ preference (₹50/month paid slot). */
  @Column({ default: false })
  isPaid: boolean;

  /** Paid slots: end of the current billing month. */
  @Column({ type: 'timestamptz', nullable: true })
  paidUntil: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
