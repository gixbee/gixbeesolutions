import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, OneToOne } from 'typeorm';
import { TalentProfile } from '../talent/talent-profile.entity';

export enum UserRole {
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
    default: UserRole.OPERATOR,
  })
  role: UserRole;

  @Column({ type: 'decimal', precision: 10, scale: 2, default: 0 })
  walletBalance: number;

  @Column({ default: false })
  isVerified: boolean;

  @Column({ nullable: true })
  profileImageUrl: string;

  @Column({ nullable: true })
  fcmToken: string;

  @Column({ default: false })
  hasWorkerProfile: boolean;

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
