import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  Unique,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';

// A user "saving" a worker to their favourites. workerId is stored as a plain
// string (the worker-profile id surfaced by /workers) rather than a hard FK so
// it stays decoupled from how a worker is sourced. The (user, workerId) pair is
// unique so the same worker can't be favourited twice.
@Entity('favourites')
@Unique(['user', 'workerId'])
export class Favourite {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  user: User;

  @Index()
  @Column()
  workerId: string;

  @CreateDateColumn()
  createdAt: Date;
}
