import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, OneToOne, JoinColumn, OneToMany } from 'typeorm';
import { User } from '../users/user.entity';
import { ProfessionalSkill } from './professional-skill.entity';

@Entity('talent_profiles')
export class TalentProfile {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @OneToOne(() => User, (user) => user.talentProfile)
  @JoinColumn()
  user: User;

  @OneToMany(() => ProfessionalSkill, (skill) => skill.talentProfile, { cascade: true })
  professionalSkills: ProfessionalSkill[];

  @Column('simple-array', { nullable: true })
  education: string[];

  @Column('simple-array', { nullable: true })
  skills: string[];

  @Column({ nullable: true })
  experience: string;

  @Column({ type: 'float', nullable: true })
  hourlyRate: number;

  @Column({ type: 'enum', enum: ['FINAL_YEAR', 'GRADUATE', 'EXPERIENCED'], nullable: true })
  currentStatus: string;

  @Column('simple-array', { nullable: true })
  preferredRoles: string[];

  @Column('simple-array', { nullable: true })
  preferredLocations: string[];

  @Column({ default: true })
  jobAlertsEnabled: boolean;

  @Column({ default: 0 })
  noShowCount: number;

  @Column({ type: 'float', default: 100 })
  searchRank: number;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
