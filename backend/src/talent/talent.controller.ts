import {
  Controller,
  Get,
  Post,
  Patch,
  Body,
  UseGuards,
  Req,
} from '@nestjs/common';
import { TalentService } from './talent.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { UpdateTalentProfileDto } from './dto/update-talent-profile.dto';
import {
  AddSkillDto,
  RemoveSkillDto,
  ToggleAlertsDto,
  ToggleSavedJobDto,
} from './dto/talent-skill.dto';
import { AadhaarGenerateOtpDto } from './dto/aadhaar-generate-otp.dto';
import { AadhaarSubmitOtpDto } from './dto/aadhaar-submit-otp.dto';

@UseGuards(JwtAuthGuard)
@Controller('talent')
export class TalentController {
  constructor(private readonly talentService: TalentService) {}

  @Get('profile')
  async getProfile(@Req() req: any) {
    return this.talentService.getProfile(req.user.userId);
  }

  // Aadhaar eKYC identity verification (credential-blocked stub).
  // Mirrors the PhonePe gateway-status pattern: the client reads status to
  // render the "Verify with Aadhaar" tile, and initiate returns a clear
  // needs-API-key payload instead of ever faking a verified result.
  @Get('verification/status')
  getVerificationStatus(@Req() req: any) {
    return this.talentService.getVerificationStatus(req.user.userId);
  }

  @Post('verification/initiate')
  initiateVerification(@Req() req: any) {
    return this.talentService.initiateVerification(req.user.userId);
  }

  @Post('verification/generate-otp')
  generateAadhaarOtp(@Req() req: any, @Body() body: AadhaarGenerateOtpDto) {
    return this.talentService.generateAadhaarOtp(
      req.user.userId,
      body.aadhaarNumber,
    );
  }

  @Post('verification/submit-otp')
  submitAadhaarOtp(@Req() req: any, @Body() body: AadhaarSubmitOtpDto) {
    return this.talentService.submitAadhaarOtp(
      req.user.userId,
      body.clientId,
      body.otp,
    );
  }

  @Post('profile')
  async updateProfile(@Req() req: any, @Body() body: UpdateTalentProfileDto) {
    return this.talentService.updateProfile(req.user.userId, body);
  }

  @Post('skills')
  async addOrUpdateSkill(@Req() req: any, @Body() body: AddSkillDto) {
    return this.talentService.addOrUpdateSkill(
      req.user.userId,
      body.skillName,
      Number(body.rate),
      body.bio,
      body.rateChart,
    );
  }

  @Post('skills/remove')
  async removeSkill(@Req() req: any, @Body() body: RemoveSkillDto) {
    return this.talentService.removeSkill(req.user.userId, body.skillId);
  }

  @Patch('alerts')
  async toggleAlerts(@Req() req: any, @Body() body: ToggleAlertsDto) {
    return this.talentService.toggleAlerts(req.user.userId, body.enabled);
  }

  // "Later" bookmark toggle for the job-alerts feed (v126 Find a Job).
  @Post('saved-jobs/toggle')
  async toggleSavedJob(@Req() req: any, @Body() body: ToggleSavedJobDto) {
    return this.talentService.toggleSavedJob(req.user.userId, body.jobId);
  }
}
