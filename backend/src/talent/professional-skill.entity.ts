import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, UpdateDateColumn, ManyToOne } from 'typeorm';
import { TalentProfile } from './talent-profile.entity';

export enum SkillApprovalStatus {
  PENDING = 'PENDING',
  APPROVED = 'APPROVED',
  REJECTED = 'REJECTED',
}

@Entity('professional_skills')
export class ProfessionalSkill {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column()
  name: string;

  @Column({ type: 'float' })
  hourlyRate: number;

  @Column({
    type: 'enum',
    enum: SkillApprovalStatus,
    default: SkillApprovalStatus.PENDING,
  })
  status: SkillApprovalStatus;

  @Column({ nullable: true })
  bio: string;

  @Column({ type: 'jsonb', nullable: true })
  rateChart: Record<string, number>;

  @ManyToOne(() => TalentProfile, (profile) => profile.professionalSkills, { onDelete: 'CASCADE' })
  talentProfile: TalentProfile;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
