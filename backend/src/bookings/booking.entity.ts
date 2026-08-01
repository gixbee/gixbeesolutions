import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';

export enum BookingStatus {
  REQUESTED = 'REQUESTED',
  CUSTOM_REQUESTED = 'CUSTOM_REQUESTED',
  PENDING = 'PENDING',
  ACCEPTED = 'ACCEPTED',
  ARRIVED = 'ARRIVED',
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

// AUDIT FIX (missing indexes): every hot path filters bookings by
// participant + status — the worker's pending queue (operator + REQUESTED),
// the customer's list, the admin monitor, the "already on a job?" guard and
// the accept-race lock. Without these, Postgres seq-scans the whole table.
@Entity('bookings')
@Index(['operator', 'status'])
@Index(['customer', 'status'])
@Index(['status', 'createdAt'])
export class Booking {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  customer: User;

  @Index()
  @ManyToOne(() => User, { nullable: true })
  operator: User;

  @Column({ nullable: true })
  skill: string;

  @Column({ nullable: true })
  serviceLocation: string;

  // Optional FK-by-id to the saved Address the customer picked for this booking.
  // Kept as a plain nullable string (not a ManyToOne relation) so a deleted
  // saved address never cascades into or orphans the booking — the booking
  // still carries the resolved free-text `serviceLocation` independently.
  @Column({ nullable: true })
  addressId: string;

  // Customer's issue description for Uber-style instant requests (selected
  // issue chips + free text) — shown to notified pros so they can decide
  // before accepting.
  @Column({ type: 'text', nullable: true })
  description: string;

  // v126 language-preference step: languages the customer needs the pro to
  // speak. Shown on the pro's incoming-job card; hard matching can start
  // once worker profiles carry their spoken languages.
  @Column('simple-array', { nullable: true })
  preferredLanguages: string[];

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true })
  totalAmount: number;

  @Column({ nullable: true })
  cancellationReason: string;

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

  /** When the booking flipped to ACCEPTED — used for cancel grace window. */
  @Column({ type: 'timestamp', nullable: true })
  acceptedAt: Date;

  @Column({ type: 'timestamp', nullable: true })
  completedAt: Date;

  @Column({ type: 'int', default: 0 })
  gpsStrikes: number;

  /** Worker GPS at accept — baseline for "is the pro moving?" checks. */
  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  acceptLat: number | null;

  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  acceptLng: number | null;

  /** Straight-line km from worker → job at accept time. */
  @Column({ type: 'decimal', precision: 8, scale: 2, nullable: true })
  acceptDistanceKm: number | null;

  /** Frozen Instant Help petrol billing values, set when the job completes. */
  @Column({ type: 'decimal', precision: 8, scale: 2, nullable: true })
  petrolDistanceKm: number | null;

  @Column({ type: 'decimal', precision: 8, scale: 2, nullable: true })
  petrolRatePerKm: number | null;

  @Column({ type: 'int', nullable: true })
  petrolAmount: number | null;

  /**
   * Set when GPS progress checks confirm the worker is not moving toward the
   * job. While set (and status still ACCEPTED), the customer may cancel free
   * with no late-cancel strike; the worker does not get a job-credit refund.
   */
  @Column({ type: 'timestamp', nullable: true })
  workerNoProgressAt: Date | null;

  @Column({ nullable: true })
  arrivalOtp: string;

  @Column({ nullable: true })
  completionOtp: string;

  @Column({ default: 'WALLET' })
  paymentMethod: string;

  @Column({ type: 'boolean', default: false })
  isPaid: boolean;

  // Manual (cash / UPI / other) post-completion confirmation — both sides
  // confirm before `isPaid` flips. Gixbee never handles the money.
  @Column({ type: 'boolean', default: false })
  workerPaidConfirmed: boolean;

  @Column({ type: 'boolean', default: false })
  customerPaidConfirmed: boolean;

  // Customer's chosen off-app method: CASH | UPI | OTHER
  @Column({ nullable: true })
  paymentCollectionMethod: string;

  // Worker honesty check: EXACT | TIP | UNDERPAID
  @Column({ nullable: true })
  workerHonestyCheck: string;

  // Customer safety check: OK | ASKED_MORE | TIP
  @Column({ nullable: true })
  customerSafetyCheck: string;

  @Column({ type: 'int', nullable: true })
  billingHours: number;

  // Full wall-clock minutes from arrival confirmation to completion.
  @Column({ type: 'int', nullable: true })
  workedMinutes: number;

  @Column({ type: 'int', nullable: true })
  rating: number;

  // ── Worker → customer rating (v126 parity: both sides rate after a job).
  @Column({ type: 'int', nullable: true })
  customerRating: number;

  /** Customer asked the worker to cancel; awaiting Approve/Decline. */
  @Column({ type: 'timestamp', nullable: true })
  cancelRequestedAt: Date;

  /** Travel compensation frozen at late-cancel ban (audit / payout). */
  @Column({ type: 'int', nullable: true })
  lateCancelCompensationAmountInr: number | null;

  @Column({ type: 'decimal', precision: 8, scale: 2, nullable: true })
  lateCancelCompensationDistanceKm: number | null;

  @Column({ type: 'timestamp', nullable: true })
  lateCancelCompensationPaidAt: Date | null;

  // ── Dispute / report (was a log-only stub; now persisted so admin review
  // and the reporter can see it). reporterRole distinguishes who filed.
  @Column({ type: 'text', nullable: true })
  disputeReason: string;

  @Column({ nullable: true })
  disputeReporterRole: string; // 'CUSTOMER' | 'WORKER'

  @Column({ type: 'timestamp', nullable: true })
  disputedAt: Date;

  // Admin resolution of a dispute (portal Disputes page).
  @Column({ type: 'text', nullable: true })
  disputeResolution: string;

  @Column({ type: 'timestamp', nullable: true })
  disputeResolvedAt: Date;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
