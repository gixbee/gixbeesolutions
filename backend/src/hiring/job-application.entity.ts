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
import { JobPost } from './job-post.entity';

export enum ApplicationStatus {
  APPLIED = 'APPLIED',
  INTERVIEW = 'INTERVIEW',
  SELECTED = 'SELECTED',
  REJECTED = 'REJECTED',
  NO_SHOW = 'NO_SHOW',
  WITHDRAWN = 'WITHDRAWN',
}

// AUDIT FIX (missing indexes): the seeker's tracker filters by applicant and
// the employer's pipeline by jobPost — both on every open.
@Entity('job_applications')
export class JobApplication {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => JobPost)
  jobPost: JobPost;

  @Index()
  @ManyToOne(() => User)
  applicant: User;

  @Column({
    type: 'enum',
    enum: ApplicationStatus,
    default: ApplicationStatus.APPLIED,
  })
  status: ApplicationStatus;

  @Column({ type: 'text', nullable: true })
  coverLetter: string;

  // Optional résumé/document the applicant attached at apply time. Stored as the
  // relative `/uploads/...` path returned by the shared upload endpoint (same as
  // avatars/certificates); a business viewer opens it from the candidate profile.
  @Column({ type: 'text', nullable: true })
  resumeUrl: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
