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

  @Column()
  name: string;

  @Column({ type: 'text', nullable: true })
  description: string;

  @Column({ nullable: true })
  imageUrl: string;

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
