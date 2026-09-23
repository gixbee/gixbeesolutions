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
import { Business } from '../businesses/business.entity';

// AUDIT FIX (missing indexes): catalog reads filter isAvailable + recency;
// the owner's "my items" filters by owner.
@Entity('rental_items')
@Index(['isAvailable', 'createdAt'])
export class RentalItem {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  owner: User;

  @ManyToOne(() => Business, { nullable: true })
  business: Business | null;

  @Column({ type: 'integer', default: 1 }) quantity: number;
  @Column({ type: 'text', default: '' }) pickupAddress: string;
  @Column({ default: false }) deliveryAvailable: boolean;
  @Column({ type: 'numeric', precision: 10, scale: 2, default: 0 }) deliveryFee: number;
  @Column({ type: 'numeric', precision: 10, scale: 2, default: 0 }) depositPerUnit: number;

  @Column({ type: 'numeric', precision: 10, scale: 2, default: 0 }) advanceAmount: number;
  @Column({ type: 'numeric', precision: 5, scale: 2, default: 0 }) advancePercent: number;
  @Column({ type: 'varchar', length: 280, default: '' }) pickupInstructions: string;
  @Column({ type: 'numeric', precision: 10, scale: 2, default: 0 }) lateFeePerHour: number;
  @Column({ type: 'varchar', length: 16, default: 'GOOD' }) condition: string;
  @Column({ type: 'varchar', length: 40, default: 'OTHER' }) category: string;
  @Column({ type: 'varchar', length: 24, default: 'FLEXIBLE' }) cancellationPolicy: string;
  @Column({ type: 'date', nullable: true }) availableFrom: string | null;
  @Column({ type: 'date', nullable: true }) availableUntil: string | null;
  @Column({ type: 'simple-array', default: '1,2,3,4,5,6,7' }) availableWeekdays: string;
  @Column({ type: 'int', nullable: true }) slotStartMinute: number | null;
  @Column({ type: 'int', nullable: true }) slotEndMinute: number | null;

  @Column({ type: 'float', nullable: true }) pickupLat: number | null;
  @Column({ type: 'float', nullable: true }) pickupLng: number | null;

  @Column()
  name: string;

  @Column({ type: 'text', nullable: true })
  description: string;

  @Column({ nullable: true })
  imageUrl: string;

  @Column({ type: 'jsonb', default: [] })
  imageUrls: string[];

  @Column({ type: 'decimal', precision: 10, scale: 2 })
  hourlyRate: number;

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true })
  dailyRate: number;

  @Column({ type: 'int', default: 1 })
  minHoursToRent: number;

  @Column({ default: true })
  isAvailable: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
