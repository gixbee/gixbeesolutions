import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { TalentProfile } from './talent-profile.entity';
import { User } from '../users/user.entity';
import {
  ProfessionalSkill,
  SkillApprovalStatus,
} from './professional-skill.entity';
import { AadhaarKycService } from './aadhaar-kyc.service';
import { WorkersService } from '../workers/workers.service';
import {
  VerificationStatus,
  WorkerProfile,
} from '../workers/worker-profile.entity';

@Injectable()
export class TalentService {
  constructor(
    @InjectRepository(TalentProfile)
    private readonly talentRepo: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepo: Repository<ProfessionalSkill>,
    @InjectRepository(WorkerProfile)
    private readonly workerRepo: Repository<WorkerProfile>,
    private readonly aadhaarKyc: AadhaarKycService,
    private readonly workersService: WorkersService,
  ) {}

  private get aadhaarConfigured(): boolean {
    return this.aadhaarKyc.isConfigured();
  }

  private async isUserAadhaarVerified(userId: string): Promise<boolean> {
    const worker = await this.workerRepo.findOne({
      where: { user: { id: userId } },
    });
    return worker?.verificationStatus === VerificationStatus.VERIFIED;
  }

  /**
   * Verification readiness for the Register-as-Pro "Verify" step.
   * Reports real verified state from worker_profiles — never fakes it.
   */
  async getVerificationStatus(userId: string) {
    const configured = this.aadhaarConfigured;
    const verified = await this.isUserAadhaarVerified(userId);
    return {
      provider: 'AADHAAR',
      available: configured,
      needsApiKey: !configured,
      verified,
      message: verified
        ? null
        : configured
          ? 'Enter your Aadhaar and confirm with the OTP on your Aadhaar-linked mobile — no DigiLocker account needed.'
          : 'Aadhaar verification is coming soon. Confirm with the OTP on your Aadhaar-linked mobile — no DigiLocker account needed. Verified pros rank higher and get more jobs. For now you can upload certificates as proof.',
    };
  }

  /**
   * Begin Aadhaar verification — returns gateway readiness; use
   * generateAadhaarOtp / submitAadhaarOtp for the live OTP flow.
   */
  async initiateVerification(userId: string) {
    const status = await this.getVerificationStatus(userId);
    if (status.verified) {
      return {
        status: 'ALREADY_VERIFIED',
        needsApiKey: false,
        provider: 'AADHAAR',
        verified: true,
        message: 'Your Aadhaar is already verified.',
      };
    }
    if (!this.aadhaarConfigured) {
      return {
        status: 'UNAVAILABLE',
        needsApiKey: true,
        provider: 'AADHAAR',
        verified: false,
        message:
          'Aadhaar verification is not live yet: the KYC provider key has not been configured. You can still upload certificates as proof for now.',
      };
    }
    return {
      status: 'READY',
      needsApiKey: false,
      provider: 'AADHAAR',
      verified: false,
      message:
        'Call POST /talent/verification/generate-otp with your 12-digit Aadhaar, then submit the OTP.',
    };
  }

  async generateAadhaarOtp(userId: string, aadhaarNumber: string) {
    if (await this.isUserAadhaarVerified(userId)) {
      return {
        status: 'ALREADY_VERIFIED',
        verified: true,
        message: 'Your Aadhaar is already verified.',
      };
    }
    const { clientId, message } = await this.aadhaarKyc.generateOtp(aadhaarNumber);
    return {
      status: 'OTP_SENT',
      clientId,
      verified: false,
      message,
    };
  }

  async submitAadhaarOtp(userId: string, clientId: string, otp: string) {
    if (await this.isUserAadhaarVerified(userId)) {
      return {
        status: 'ALREADY_VERIFIED',
        verified: true,
        message: 'Your Aadhaar is already verified.',
      };
    }
    const result = await this.aadhaarKyc.submitOtp(clientId, otp);
    await this.workersService.recordAadhaarVerification(userId, {
      maskedAadhaar: result.maskedAadhaar,
      fullName: result.fullName,
    });
    return {
      status: 'VERIFIED',
      verified: true,
      maskedAadhaar: result.maskedAadhaar,
      fullName: result.fullName,
      message: 'Aadhaar verified successfully. You can now go live after admin review if required.',
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
