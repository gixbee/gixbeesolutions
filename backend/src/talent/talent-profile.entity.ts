import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToOne,
  JoinColumn,
  OneToMany,
} from 'typeorm';
import { User } from '../users/user.entity';
import { ProfessionalSkill } from './professional-skill.entity';

@Entity('talent_profiles')
export class TalentProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @OneToOne(() => User, (user) => user.talentProfile)
  @JoinColumn()
  user: User;

  @OneToMany(() => ProfessionalSkill, (skill) => skill.talentProfile, {
    cascade: true,
  })
  professionalSkills: ProfessionalSkill[];

  @Column('simple-array', { nullable: true })
  education: string[];

  @Column('simple-array', { nullable: true })
  skills: string[];

  // Profile photo URL (uploaded via POST /uploads/image, then saved here).
  @Column({ nullable: true })
  photoUrl: string;

  // Certificate/document image URLs (uploaded via POST /uploads/image).
  @Column('simple-array', { nullable: true })
  certificates: string[];

  @Column({ nullable: true })
  experience: string;

  @Column({ type: 'float', nullable: true })
  hourlyRate: number;

  @Column({
    type: 'enum',
    enum: ['FINAL_YEAR', 'GRADUATE', 'EXPERIENCED'],
    nullable: true,
  })
  currentStatus: string;

  // Expected monthly salary in ₹ (v126 Find a Job wizard "salary" step).
  // Distinct from hourlyRate, which is the Earn Hourly per-hour rate.
  @Column({ type: 'int', nullable: true })
  expectedSalary: number;

  @Column('simple-array', { nullable: true })
  preferredRoles: string[];

  @Column('simple-array', { nullable: true })
  preferredLocations: string[];

  @Column({ default: true })
  jobAlertsEnabled: boolean;

  // Job posts bookmarked via "Later" in the alerts feed (v126 Find a Job).
  // Plain id list (not a relation) — the feed already has the posts loaded.
  @Column('simple-array', { nullable: true })
  savedJobIds: string[];

  @Column({ default: 0 })
  noShowCount: number;

  @Column({ type: 'float', default: 100 })
  searchRank: number;

  @Column({ type: 'float', nullable: true })
  lat: number | null;

  @Column({ type: 'float', nullable: true })
  lng: number | null;

  @Column({ type: 'float', default: 25 })
  travelRadiusKm: number;

  @Column({ default: 'IMMEDIATE' })
  availability: string;

  @Column({ type: 'timestamptz', nullable: true })
  lastActiveAt: Date | null;

  @Column({ default: 'ACTIVE' })
  profileStatus: string;

  @Column({ nullable: true })
  preferredWorkMode: string | null;

  @Column({ default: 'MONTHLY' })
  expectedSalaryPeriod: string;

  @Column('simple-array', { nullable: true })
  employmentTypes: string[];

  @Column({ type: 'date', nullable: true })
  availableOn: string | null;

  @Column({ nullable: true })
  resumeUrl: string | null;

  @Column({ nullable: true })
  resumeFileName: string | null;

  @Column({ nullable: true })
  resumeMimeType: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  resumeUploadedAt: Date | null;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
