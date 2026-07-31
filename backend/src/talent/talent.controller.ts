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

@UseGuards(JwtAuthGuard)
@Controller('talent')
export class TalentController {
  constructor(private readonly talentService: TalentService) {}

  @Get('profile')
  async getProfile(@Req() req: any) {
    return this.talentService.getProfile(req.user.userId);
  }

  // DigiLocker identity verification (Phase 5 — credential-blocked stub).
  // Mirrors the PhonePe gateway-status pattern: the client reads status to
  // render the "Verify with DigiLocker" tile, and initiate returns a clear
  // needs-API-key payload instead of ever faking a verified result.
  @Get('verification/status')
  getVerificationStatus() {
    return this.talentService.getVerificationStatus();
  }

  @Post('verification/initiate')
  initiateVerification(@Req() req: any) {
    return this.talentService.initiateVerification(req.user.userId);
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
