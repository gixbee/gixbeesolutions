import {
  Entity, PrimaryGeneratedColumn, Column, CreateDateColumn,
  UpdateDateColumn, OneToOne, JoinColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

export enum VerificationStatus {
  PENDING = 'PENDING',
  VERIFIED = 'VERIFIED',
  REJECTED = 'REJECTED',
}

@Entity('worker_profiles')
export class WorkerProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @OneToOne(() => User)
  @JoinColumn()
  user: User;

  @Column('simple-array', { nullable: true })
  skills: string[];

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

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
