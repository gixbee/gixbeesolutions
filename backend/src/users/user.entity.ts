import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToOne,
} from 'typeorm';
import { Exclude } from 'class-transformer';
import { TalentProfile } from '../talent/talent-profile.entity';

export enum UserRole {
  CUSTOMER = 'CUSTOMER',
  OWNER = 'OWNER',
  OPERATOR = 'OPERATOR',
  ADMIN = 'ADMIN',
}

export enum UserApprovalStatus {
  PENDING = 'PENDING',
  APPROVED = 'APPROVED',
  REJECTED = 'REJECTED',
}

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  phoneNumber: string;

  @Column({ nullable: true })
  name: string;

  @Column({
    type: 'enum',
    enum: UserRole,
    default: UserRole.CUSTOMER,
  })
  role: UserRole;

  // AUDIT FIX: private fields must never ride along when a User is embedded
  // as a relation (booking.customer/operator, job.employer, rental.owner…).
  // The global ClassSerializerInterceptor (main.ts) strips @Exclude'd fields
  // from every entity response. Own wallet balance is served by the wallets
  // endpoints; own profile is a hand-built object in auth.service (unaffected).
  @Exclude()
  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  walletBalance: number;

  @Column({ default: false })
  isVerified: boolean;

  @Column({ nullable: true })
  profileImageUrl: string;

  @Exclude()
  @Column({ nullable: true })
  fcmToken: string;

  @Column({ default: false })
  hasWorkerProfile: boolean;

  @Column({ default: true })
  isAvailableForWork: boolean;

  /** Forced late-cancels after accept grace (worker-approved cancels do not count). */
  @Column({ type: 'int', default: 0 })
  lateCancelStrikeCount: number;

  /** Instant Help blocked until travel compensation is paid. */
  @Column({ default: false })
  instantHelpBlocked: boolean;

  /** Booking that triggered the ban — compensation payout goes to its worker. */
  @Column({ type: 'uuid', nullable: true })
  unblockCompensationBookingId: string | null;

  /** Frozen INR amount owed to unlock Instant Help. */
  @Column({ type: 'int', nullable: true })
  unblockCompensationAmountInr: number | null;

  /** Distance used when freezing compensation (for UI). */
  @Column({ type: 'decimal', precision: 8, scale: 2, nullable: true })
  unblockCompensationDistanceKm: number | null;

  @Column({
    type: 'enum',
    enum: UserApprovalStatus,
    default: UserApprovalStatus.PENDING,
  })
  approvalStatus: UserApprovalStatus;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;

  @OneToOne(() => TalentProfile, (profile) => profile.user)
  talentProfile: TalentProfile;
}
