import { Controller, Get, Post, Patch, Body, UseGuards, Req } from '@nestjs/common';
import { TalentService } from './talent.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@UseGuards(JwtAuthGuard)
@Controller('talent')
export class TalentController {
  constructor(private readonly talentService: TalentService) {}

  @Get('profile')
  async getProfile(@Req() req: any) {
    return this.talentService.getProfile(req.user.userId);
  }

  @Post('profile')
  async updateProfile(@Req() req: any, @Body() body: any) {
    return this.talentService.updateProfile(req.user.userId, body);
  }

  @Post('skills')
  async addOrUpdateSkill(@Req() req: any, @Body('skillName') skillName: string, @Body('rate') rate: number) {
    return this.talentService.addOrUpdateSkill(req.user.userId, skillName, Number(rate));
  }

  @Post('skills/remove')
  async removeSkill(@Req() req: any, @Body('skillId') skillId: string) {
    return this.talentService.removeSkill(req.user.userId, skillId);
  }

  @Patch('alerts')
  async toggleAlerts(@Req() req: any, @Body('enabled') enabled: boolean) {
    return this.talentService.toggleAlerts(req.user.userId, enabled);
  }
}
