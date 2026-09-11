import { Entity, PrimaryGeneratedColumn, Column, ManyToOne, JoinColumn, Unique, Index } from 'typeorm';
import { Booking } from './booking.entity';
@Entity('booking_deadlines')
@Unique(['bookingId', 'kind', 'sequence'])
@Index('booking_deadlines_due', ['dueAt'], { where: '"processedAt" IS NULL' })
export class BookingDeadline {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column('uuid') bookingId: string;
  @ManyToOne(() => Booking, { nullable: false }) @JoinColumn({ name: 'bookingId' }) booking: Booking;
  @Column({ type: 'varchar', length: 20 }) kind: string;
  @Column('integer') sequence: number;
  @Column('timestamptz') dueAt: Date;
  @Column({ type: 'timestamptz', nullable: true }) processedAt: Date | null;
  @Column({ type: 'integer', default: 0 }) attempts: number;
  @Column({ type: 'text', nullable: true }) lastError: string | null;
}
