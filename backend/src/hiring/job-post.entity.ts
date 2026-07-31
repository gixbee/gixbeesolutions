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

// AUDIT FIX (missing indexes): the seeker feed reads active posts ordered by
// recency on every open; the employer's dashboard filters by employer.
@Entity('job_posts')
@Index(['isActive', 'createdAt'])
export class JobPost {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => User)
  employer: User;

  @Column()
  title: string;

  @Column({ type: 'text' })
  description: string;

  @Column('simple-array', { nullable: true })
  requiredSkills: string[];

  // Posting-form fields the app always sent but the backend used to drop —
  // now persisted so seeker-side filters work on real data (2026-07-13).
  @Column({ nullable: true })
  jobType: string; // e.g. 'Full Time' | 'Part Time' | 'Contract' | 'Internship'

  @Column({ nullable: true })
  experience: string; // e.g. 'Fresher' | '1-3 Years' | …

  @Column({ nullable: true })
  location: string; // free-text city/area

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true })
  salaryMin: number;

  @Column({ type: 'decimal', precision: 10, scale: 2, nullable: true })
  salaryMax: number;

  @Column({ default: true })
  isActive: boolean;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
