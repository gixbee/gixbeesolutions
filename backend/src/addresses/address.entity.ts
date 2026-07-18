import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  Index,
} from 'typeorm';
import { User } from '../users/user.entity';

// A saved delivery/booking address belonging to a user. The full address text
// is stored as a single `line` string (the booking flow collects one free-text
// field); `label` is an optional short tag ("Home", "Work"). Scoped to the
// owning user via a CASCADE ManyToOne so a user's addresses are removed with
// the account. No uniqueness constraint — a user may save the same place twice
// under different labels, and de-duping is a client concern.
@Entity('addresses')
export class Address {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  user: User;

  @Column({ nullable: true })
  label: string;

  @Column()
  line: string;

  @CreateDateColumn()
  createdAt: Date;
}
