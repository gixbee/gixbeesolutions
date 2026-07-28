import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

export enum WorkerStrikeType {
  /** Booking forfeited after 3 GPS strikes (didn't move toward the job). */
  GPS_FORFEIT = 'GPS_FORFEIT',
  /** Accepted but never arrived / never verified arrival OTP. */
  NO_SHOW = 'NO_SHOW',
  /** Manually issued from the admin portal. */
  ADMIN = 'ADMIN',
}

export enum WorkerStrikeStatus {
  /** Counts toward the suspension threshold. */
  ACTIVE = 'ACTIVE',
  /** Worker filed an appeal — awaiting admin review. Still counts. */
  APPEALED = 'APPEALED',
  /** Admin overturned it — no longer counts toward suspension. */
  OVERTURNED = 'OVERTURNED',
  /** Admin reviewed the appeal and kept the strike. Counts. */
  UPHELD = 'UPHELD',
}

/**
 * Per-incident strike ledger.
 *
 * WHY (worker fairness + regulation): the old flow silently incremented
 * `WorkerProfile.strikeCount` and deactivated at 3 with no written reason and
 * no appeal path. Karnataka's 2025 gig-worker Act (the likely template for a
 * future Kerala law) requires written reasons + notice before deactivation,
 * and ratings/penalty opacity is the #1 driver of platform-worker protests.
 * Every strike now carries a reason the worker can read, and an appeal an
 * admin must resolve. Suspension = 3+ counting strikes blocks Go Live (see
 * WorkersService.toggleGoLive); an overturned appeal lifts it immediately.
 */
@Entity('worker_strikes')
@Index(['workerUserId'])
@Index(['status'])
export class WorkerStrike {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  /** User id of the worker (matches WorkerProfile.user). */
  @Column()
  workerUserId: string;

  /** Booking that triggered the strike, when applicable. */
  @Column({ type: 'uuid', nullable: true })
  bookingId: string | null;

  @Column({ type: 'enum', enum: WorkerStrikeType })
  type: WorkerStrikeType;

  /** Human-readable reason SHOWN TO THE WORKER — never leave generic. */
  @Column({ type: 'text' })
  reason: string;

  @Column({
    type: 'enum',
    enum: WorkerStrikeStatus,
    default: WorkerStrikeStatus.ACTIVE,
  })
  status: WorkerStrikeStatus;

  /** Worker's appeal text (one appeal per strike). */
  @Column({ type: 'text', nullable: true })
  appealMessage: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  appealedAt: Date | null;

  /** Admin's note when resolving an appeal (shown to the worker). */
  @Column({ type: 'text', nullable: true })
  resolutionNote: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  resolvedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;
}
