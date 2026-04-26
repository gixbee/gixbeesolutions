import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne } from 'typeorm';
import { User } from '../users/user.entity';

export enum BookingStatus {
  REQUESTED = 'REQUESTED',
  CUSTOM_REQUESTED = 'CUSTOM_REQUESTED',
  PENDING = 'PENDING',
  ACCEPTED = 'ACCEPTED',
  CONFIRMED = 'CONFIRMED',
  ACTIVE = 'ACTIVE',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
  REJECTED = 'REJECTED',
}

export enum BookingType {
  PACKAGE = 'PACKAGE',
  CUSTOM = 'CUSTOM',
  INSTANT = 'INSTANT',
  RENTAL = 'RENTAL',
}

@Entity('bookings')
export class Booking {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User)
  customer: User;

  @ManyToOne(() => User, { nullable: true })
  operator: User;

  @Column({ nullable: true })
  skill: string;

  @Column({ nullable: true })
  serviceLocation: string;

  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  serviceLat: number;

  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  serviceLng: number;

  @Column({ type: 'jsonb', nullable: true })
  onSiteContact: {
    name: string;
    relation: string;
    phone: string;
  };

  @Column({
    type: 'enum',
    enum: BookingType,
    default: BookingType.INSTANT,
  })
  type: BookingType;

  @Column({ type: 'jsonb', nullable: true })
  customDetails: {
    eventType: string;
    guestCount: number;
    specialNeeds: string;
  };

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true })
  quote: number;

  @Column({ nullable: true })
  vendorNote: string;

  @Column({
    type: 'enum',
    enum: BookingStatus,
    default: BookingStatus.PENDING,
  })
  status: BookingStatus;

  @Column({ type: 'decimal', precision: 10, scale: 2 })
  amount: number;

  @Column({ type: 'timestamp', nullable: true })
  scheduledAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  startedAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  completedAt: Date;

  @Column({ type: 'int', default: 0 })
  gpsStrikes: number;

  @Column({ nullable: true })
  arrivalOtp: string;

  @Column({ nullable: true })
  completionOtp: string;

  @Column({ type: 'int', nullable: true })
  billingHours: number;

  @Column({ type: 'int', nullable: true })
  rating: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
