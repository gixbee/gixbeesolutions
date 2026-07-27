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

  // Confirmed map-pin coordinates for this address. Written when the user
  // pins it on the LocationPinScreen (either while saving, or backfilled the
  // first time they reuse a coord-less saved address in Instant Help).
  // Nullable: legacy rows and addresses saved outside the pin flow have no
  // coords — those still require a pin confirm before dispatch, because the
  // pin is the ONLY coordinate the booking flow trusts (typed text is just a
  // human-readable label; forward-geocoding Kerala addresses is unreliable).
  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  lat: number;

  @Column({ type: 'decimal', precision: 9, scale: 6, nullable: true })
  lng: number;

  @CreateDateColumn()
  createdAt: Date;
}
