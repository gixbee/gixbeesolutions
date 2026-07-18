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

// General support ticket — the channel for ANY user issue that isn't tied to
// a booking (those go through /bookings/:id/dispute). Filed from the app's
// Help & Support screen; answered from the admin portal's Support inbox.
@Entity('support_tickets')
export class SupportTicket {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  user: User;

  @Column()
  subject: string;

  @Column({ type: 'text' })
  message: string;

  @Column({ default: 'OPEN' })
  status: string; // 'OPEN' | 'RESOLVED'

  // Admin's reply, shown to the user in the app's My Tickets list.
  @Column({ type: 'text', nullable: true })
  reply: string;

  @Column({ type: 'timestamp', nullable: true })
  resolvedAt: Date;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
