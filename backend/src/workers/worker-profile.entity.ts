import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  UpdateDateColumn, OneToOne, JoinColumn, Index,
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

  /// Languages the pro speaks (v126 language matching). Null/empty =
  /// unknown — such pros are still notified (lenient matching) so legacy
  /// profiles aren't starved of jobs until they set this in Go Live.
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
