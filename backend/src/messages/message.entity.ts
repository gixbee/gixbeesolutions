import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';

/**
 * A single chat message between two users.
 *
 * Conversations are implicit: the thread between users A and B is every
 * Message where {sender,recipient} == {A,B}. An optional [bookingId] links a
 * message to the booking it was started from (chat-from-booking entry point).
 */
@Entity('messages')
export class Message {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User, { eager: true, onDelete: 'CASCADE' })
  sender: User;

  @Index()
  @ManyToOne(() => User, { eager: true, onDelete: 'CASCADE' })
  recipient: User;

  @Column({ type: 'text' })
  body: string;

  @Column({ type: 'uuid', nullable: true })
  bookingId: string | null;

  @Column({ default: false })
  isRead: boolean;

  @CreateDateColumn()
  createdAt: Date;
}
