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
import { RentalItem } from './rental-item.entity';

export enum RentalStatus {
  PENDING = 'PENDING',
  CONFIRMED = 'CONFIRMED',
  ACTIVE = 'ACTIVE',
  COMPLETED = 'COMPLETED',
  CANCELLED = 'CANCELLED',
  REJECTED = 'REJECTED',
}

// AUDIT FIX (missing indexes): the overlap check (item + CONFIRMED/ACTIVE +
// time window) runs on EVERY reserve and confirm; the renter's list and the
// owner's queue filter by participant. Composite index below backs the
// overlap query; the time columns keep the range scan cheap.
@Entity('rental_reservations')
@Index(['item', 'status'])
@Index(['item', 'status', 'startTime'])
export class RentalReservation {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => RentalItem)
  item: RentalItem;

  @Index()
  @ManyToOne(() => User)
  renter: User;

  @Column({ type: 'timestamp' })
  startTime: Date;

  @Column({ type: 'timestamp' })
  endTime: Date;

  @Column({ type: 'decimal', precision: 10, scale: 2 })
  totalPrice: number;

  @Column({
    type: 'enum',
    enum: RentalStatus,
    default: RentalStatus.PENDING,
  })
  status: RentalStatus;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
