import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';

export enum VerificationStatus {
  PENDING = 'PENDING',
  VERIFIED = 'VERIFIED',
  REJECTED = 'REJECTED',
}

// AUDIT FIX (missing index): the admin verification queue filters by
// verificationStatus; dispatch/DB fallbacks look profiles up by user (the
// OneToOne JoinColumn is already unique-indexed by Postgres).
@Entity('worker_profiles')
@Index(['verificationStatus'])
export class WorkerProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @OneToOne(() => User)
  @JoinColumn()
  user: User;

  @Column('simple-array', { nullable: true })
  skills: string[];

  /// Subset of [skills] the worker has switched ON for instant dispatch.
  /// Null/empty = all skills active (back-compat with profiles created
  /// before per-service activation existed).
  @Column('simple-array', { nullable: true })
  activeSkills: string[];

  /// Languages the pro speaks (v126 language matching). Going live requires
  /// at least one. Null/empty on a legacy live pro is still matched
  /// leniently so they are not starved of jobs until they go offline.
  @Column('simple-array', { nullable: true })
  languages: string[];

  /// How far the pro is willing to travel for an instant job, in km.
  /// The broadcast fan-out only pings a pro when the job is inside THIS
  /// radius (see WorkersService.getNearby). Capped server-side at
  /// MAX_DISPATCH_RADIUS_KM so nobody can opt into the whole state.
  @Column({ type: 'int', default: 10 })
  serviceRadiusKm: number;

  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  hourlyRate: number;

  @Column({ type: 'jsonb', nullable: true })
  availabilitySchedule: Record<string, { start: string; end: string }>;

  @Column({ default: false })
  isActive: boolean;

  @Column({ type: 'int', default: 0 })
  goLiveToggleCountToday: number;

  @Column({ type: 'date', nullable: true })
  goLiveToggleDate: string;

  /// Periodic fee model ("N jobs, then pay"): COMPLETED jobs consumed in the
  /// current period. Gate: >= go_live_jobs_per_payment blocks Go Live until
  /// payPeriodFee() resets it. Only incremented while the model is enabled,
  /// so switching it on later starts every worker at 0 (first period free).
  @Column({ type: 'int', default: 0 })
  jobsSincePayment: number;

  @Column({ default: false })
  isFirstJobDone: boolean;

  @Column({ type: 'int', default: 0 })
  noShowCount: number;

  @Column({ type: 'int', default: 0 })
  strikeCount: number;

  @Column({ type: 'int', default: 0 })
  rateUpdateCountToday: number;

  @Column({ type: 'date', nullable: true })
  rateUpdateDate: string;

  @Column({
    type: 'enum',
    enum: VerificationStatus,
    default: VerificationStatus.PENDING,
  })
  verificationStatus: VerificationStatus;

  /// Masked UID reference after successful Aadhaar eKYC (never store full number).
  @Column({ type: 'varchar', length: 32, nullable: true })
  maskedAadhaar: string | null;

  @Column({ nullable: true })
  bio: string;

  @Column({ nullable: true })
  title: string;

  @Column({ type: 'decimal', precision: 3, scale: 2, default: 0 })
  rating: number;

  @Column({ type: 'int', default: 0 })
  completedJobs: number;

  @Column({ type: 'int', default: 0 })
  reviewCount: number;

  @Column('simple-array', { nullable: true })
  availabilityTags: string[];

  @Column({ type: 'decimal', precision: 10, scale: 7, nullable: true })
  lastLat: number;

  @Column({ type: 'decimal', precision: 10, scale: 7, nullable: true })
  lastLng: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
