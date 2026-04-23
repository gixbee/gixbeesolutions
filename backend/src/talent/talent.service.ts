import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TalentProfile } from './talent-profile.entity';
import { User } from '../users/user.entity';
import { ProfessionalSkill, SkillApprovalStatus } from './professional-skill.entity';

@Injectable()
export class TalentService {
  constructor(
    @InjectRepository(TalentProfile)
    private readonly talentRepo: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepo: Repository<ProfessionalSkill>,
  ) {}

  async getProfile(userId: string): Promise<TalentProfile> {
    const profile = await this.talentRepo.findOne({ 
      where: { user: { id: userId } } as any,
      relations: ['user', 'professionalSkills']
    });
    if (!profile) {
      const newProfile = this.talentRepo.create({
        user: { id: userId } as User,
      });
      return this.talentRepo.save(newProfile);
    }
    return profile;
  }

  async updateProfile(userId: string, data: Partial<TalentProfile>): Promise<TalentProfile> {
    const profile = await this.getProfile(userId);
    Object.assign(profile, data);
    return this.talentRepo.save(profile);
  }

  async addOrUpdateSkill(userId: string, skillName: string, rate: number): Promise<ProfessionalSkill> {
    const profile = await this.getProfile(userId);
    let skill = await this.skillRepo.findOne({
      where: { talentProfile: { id: profile.id }, name: skillName }
    });

    if (skill) {
      skill.hourlyRate = rate;
      skill.status = SkillApprovalStatus.PENDING; // Reset status on rate update? Or keep if approved?
    } else {
      skill = this.skillRepo.create({
        talentProfile: profile,
        name: skillName,
        hourlyRate: rate,
        status: SkillApprovalStatus.PENDING,
      });
    }

    return this.skillRepo.save(skill);
  }

  async removeSkill(userId: string, skillId: string): Promise<void> {
    const profile = await this.getProfile(userId);
    const skill = await this.skillRepo.findOne({
      where: { id: skillId, talentProfile: { id: profile.id } }
    });
    if (!skill) throw new NotFoundException('Skill not found in your profile');
    await this.skillRepo.remove(skill);
  }

  async updateSkillStatus(skillId: string, status: SkillApprovalStatus): Promise<ProfessionalSkill> {
    const skill = await this.skillRepo.findOne({ where: { id: skillId } });
    if (!skill) throw new NotFoundException('Skill not found');
    skill.status = status;
    return this.skillRepo.save(skill);
  }

  async toggleAlerts(userId: string, enabled: boolean): Promise<TalentProfile> {
    return this.updateProfile(userId, { jobAlertsEnabled: enabled });
  }

  // DEFECT-010: Record no-show and reduce search rank
  async recordNoShow(userId: string): Promise<void> {
    const profile = await this.talentRepo.findOne({
      where: { user: { id: userId } } as any,
    });
    if (!profile) return;
    profile.noShowCount = (profile.noShowCount || 0) + 1;
    profile.searchRank = Math.max(0, (profile.searchRank || 100) - 10);
    await this.talentRepo.save(profile);
  }
}
