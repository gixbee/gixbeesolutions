import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  Index,
  Unique,
} from 'typeorm';
import { User } from '../../users/user.entity';
import { HiringRequest } from './hiring-request.entity';
import { JobPreference } from './job-preference.entity';

export enum CandidateResponse {
  /** Notified, hasn't answered yet. */
  PENDING = 'PENDING',
  INTERESTED = 'INTERESTED',
  NOT_INTERESTED = 'NOT_INTERESTED',
}

export enum EmployerDecision {
  PENDING = 'PENDING',
  SHORTLISTED = 'SHORTLISTED',
  REJECTED = 'REJECTED',
  HIRED = 'HIRED',
}

/**
 * One notified candidate on one hiring request.
 * Created when a batch notification goes out (response=PENDING); only rows
 * with response=INTERESTED ever reach the employer's shortlist. The
 * employer's decision flows back to the candidate as their hiring status.
 */
@Entity('hiring_interests')
@Unique(['request', 'candidate'])
export class HiringInterest {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index()
  @ManyToOne(() => HiringRequest)
  request: HiringRequest;

  @Index()
  @ManyToOne(() => User)
  candidate: User;

  /** The preference profile that matched (for showing salary/skills to the employer). */
  @ManyToOne(() => JobPreference, { nullable: true })
  preference: JobPreference | null;

  @Column({
    type: 'enum',
    enum: CandidateResponse,
    default: CandidateResponse.PENDING,
  })
  response: CandidateResponse;

  @Column({
    type: 'enum',
    enum: EmployerDecision,
    default: EmployerDecision.PENDING,
  })
  decision: EmployerDecision;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  progress: Record<string, unknown>;

  @Column({ type: 'integer', default: 0 })
  revision: number;

  @Column({ type: 'timestamptz', nullable: true })
  notifiedAt: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  respondedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
