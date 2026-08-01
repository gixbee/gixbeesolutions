import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ConfigService } from '@nestjs/config';
import { TalentProfile } from './talent-profile.entity';
import { User } from '../users/user.entity';
import {
  ProfessionalSkill,
  SkillApprovalStatus,
} from './professional-skill.entity';

@Injectable()
export class TalentService {
  constructor(
    @InjectRepository(TalentProfile)
    private readonly talentRepo: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepo: Repository<ProfessionalSkill>,
    private readonly config: ConfigService,
  ) {}

  /**
   * Aadhaar eKYC identity verification — stub (credential-blocked).
   *
   * Prefer Aadhaar OTP over DigiLocker: every adult in India has Aadhaar;
   * DigiLocker is optional. Not live until a KYC provider key is configured
   * (Cashfree / Surepass / HyperVerge / etc.). Status/initiate mirror the
   * PhonePe gateway stub — client never sees a fake verified result.
   *
   * // TODO: set AADHAAR_CLIENT_ID + AADHAAR_CLIENT_SECRET (or provider
   * //       equivalents), then implement Aadhaar OTP send/verify eKYC.
   */
  private get aadhaarConfigured(): boolean {
    return Boolean(
      this.config.get<string>('AADHAAR_CLIENT_ID') &&
      this.config.get<string>('AADHAAR_CLIENT_SECRET'),
    );
  }

  /**
   * Verification readiness for the Register-as-Pro "Verify" step.
   * `verified` is always false here: with no provider configured no real
   * verification can have happened, so this never reports a fake verified
   * state. The Flutter app branches on `needsApiKey` to show the shell.
   */
  getVerificationStatus() {
    const configured = this.aadhaarConfigured;
    return {
      provider: 'AADHAAR',
      available: configured,
      needsApiKey: !configured,
      verified: false,
      message: configured
        ? null
        : 'Aadhaar verification is coming soon. Confirm with the OTP on your Aadhaar-linked mobile — no DigiLocker account needed. Verified pros rank higher and get more jobs. For now you can upload certificates as proof.',
    };
  }

  /**
   * Begin Aadhaar verification — stubbed until credentials exist.
   * Never returns a verified result: when unconfigured it returns an explicit
   * needs-API-key payload (HTTP 200 so the client can branch cleanly).
   */
  initiateVerification(_userId: string) {
    if (!this.aadhaarConfigured) {
      // TODO: wire Aadhaar OTP eKYC once AADHAAR_CLIENT_ID/SECRET exist.
      return {
        status: 'UNAVAILABLE',
        needsApiKey: true,
        provider: 'AADHAAR',
        verified: false,
        message:
          'Aadhaar verification is not live yet: the KYC provider key has not been configured. You can still upload certificates as proof for now.',
      };
    }

    // Credentials exist but the real OTP/eKYC flow is still to be written —
    // refuse rather than pretend the identity was verified.
    return {
      status: 'NOT_IMPLEMENTED',
      needsApiKey: false,
      provider: 'AADHAAR',
      verified: false,
      message:
        'Aadhaar KYC credentials detected, but the OTP verification flow is not implemented yet.',
    };
  }

  async getProfile(userId: string): Promise<TalentProfile> {
    const profile = await this.talentRepo.findOne({
      where: { user: { id: userId } } as any,
      relations: ['user', 'professionalSkills'],
    });
    if (!profile) {
      const newProfile = this.talentRepo.create({
        user: { id: userId } as User,
      });
      return this.talentRepo.save(newProfile);
    }
    return profile;
  }

  async updateProfile(
    userId: string,
    data: Partial<TalentProfile>,
  ): Promise<TalentProfile> {
    const profile = await this.getProfile(userId);
    Object.assign(profile, data);
    return this.talentRepo.save(profile);
  }

  async addOrUpdateSkill(
    userId: string,
    skillName: string,
    rate: number,
    bio: string,
    rateChart?: Record<string, number>,
  ): Promise<ProfessionalSkill> {
    const profile = await this.getProfile(userId);
    let skill = await this.skillRepo.findOne({
      where: { talentProfile: { id: profile.id }, name: skillName },
    });

    if (skill) {
      skill.hourlyRate = rate;
      if (bio !== undefined) skill.bio = bio;
      if (rateChart !== undefined) skill.rateChart = rateChart;
      skill.status = SkillApprovalStatus.PENDING; // Reset status on rate update? Or keep if approved?
    } else {
      skill = this.skillRepo.create({
        talentProfile: profile,
        name: skillName,
        hourlyRate: rate,
        bio: bio,
        rateChart: rateChart,
        status: SkillApprovalStatus.PENDING,
      });
    }

    return this.skillRepo.save(skill);
  }

  async removeSkill(userId: string, skillId: string): Promise<void> {
    const profile = await this.getProfile(userId);
    const skill = await this.skillRepo.findOne({
      where: { id: skillId, talentProfile: { id: profile.id } },
    });
    if (!skill) throw new NotFoundException('Skill not found in your profile');
    await this.skillRepo.remove(skill);
  }

  async updateSkillStatus(
    skillId: string,
    status: SkillApprovalStatus,
  ): Promise<ProfessionalSkill> {
    const skill = await this.skillRepo.findOne({ where: { id: skillId } });
    if (!skill) throw new NotFoundException('Skill not found');
    skill.status = status;
    return this.skillRepo.save(skill);
  }

  async toggleAlerts(userId: string, enabled: boolean): Promise<TalentProfile> {
    return this.updateProfile(userId, { jobAlertsEnabled: enabled });
  }

  // "Later" bookmark in the job-alerts feed (v126 Find a Job): toggles a job
  // post id in savedJobIds. Returns the updated list so the client can render
  // optimistically without a refetch.
  async toggleSavedJob(
    userId: string,
    jobId: string,
  ): Promise<{ savedJobIds: string[] }> {
    const profile = await this.getProfile(userId); // auto-creates when missing
    const current = profile.savedJobIds ?? [];
    const savedJobIds = current.includes(jobId)
      ? current.filter((id) => id !== jobId)
      : [...current, jobId];
    profile.savedJobIds = savedJobIds;
    await this.talentRepo.save(profile);
    return { savedJobIds };
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
