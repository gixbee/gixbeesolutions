import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne } from 'typeorm';
import { User } from '../users/user.entity';
import { JobPost } from './job-post.entity';

export enum ApplicationStatus {
  APPLIED = 'APPLIED',
  INTERVIEW = 'INTERVIEW',
  SELECTED = 'SELECTED',
  REJECTED = 'REJECTED',
  NO_SHOW = 'NO_SHOW',
}

@Entity('job_applications')
export class JobApplication {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => JobPost)
  jobPost: JobPost;

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

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
