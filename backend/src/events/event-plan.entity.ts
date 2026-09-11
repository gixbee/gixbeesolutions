import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn,
  ManyToOne, JoinColumn, Index, Check } from 'typeorm';
import { User } from '../users/user.entity';
import { City } from '../cities/city.entity';

@Entity('event_plans')
@Index('event_plans_customer', ['customerId', 'createdAt'])
@Check('"endTime" > "startTime"')
@Check('"guestCount" BETWEEN 1 AND 100000')
@Check("jsonb_typeof(services) = 'array'")
export class EventPlan {
  @PrimaryGeneratedColumn('uuid') id: string;
  @Column('uuid') customerId: string;
  @ManyToOne(() => User, { nullable: false }) @JoinColumn({ name: 'customerId' }) customer: User;
  @Column({ type: 'varchar', length: 100 }) eventType: string;
  @Column('timestamptz') startTime: Date;
  @Column('timestamptz') endTime: Date;
  @Column('integer') guestCount: number;
  @Column('text') location: string;
  @Column({ type: 'uuid', nullable: true }) cityId: string | null;
  @ManyToOne(() => City, { nullable: true }) @JoinColumn({ name: 'cityId' }) city: City | null;
  @Column('jsonb') services: string[];
  @Column({ type: 'text', default: '' }) notes: string;
  @Column({ type: 'timestamptz', nullable: true }) cancelledAt: Date | null;
  @CreateDateColumn({ type: 'timestamptz' }) createdAt: Date;
  @UpdateDateColumn({ type: 'timestamptz' }) updatedAt: Date;
}
