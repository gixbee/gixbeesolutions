import { Controller, Get, Patch, Param, Body, UseGuards } from '@nestjs/common';
import { UsersService } from './users.service';
import { TalentService } from '../talent/talent.service';
import { UserApprovalStatus, UserRole } from './user.entity';
import { SkillApprovalStatus } from '../talent/professional-skill.entity';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('admin-user-list')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly talentService: TalentService,
  ) {}

  @Get('summary')
  async getSummary() {
    return this.usersService.getSystemSummary();
  }

  @Get()
  async getAllUsers() {
    console.log('DEBUG: UsersController.getAllUsers() called');
    const users = await this.usersService.findAll();
    console.log(`DEBUG: Found ${users.length} users`);
    return users;
  }

  @Get(':id')
  async getUser(@Param('id') id: string) {
    return this.usersService.findById(id);
  }

  @Get(':id/stats')
  async getUserStats(@Param('id') id: string) {
    return this.usersService.getUserStats(id);
  }

  @Patch(':id')
  async updateProfile(@Param('id') id: string, @Body() data: { name?: string; profileImageUrl?: string; isAvailableForWork?: boolean; role?: UserRole; hasWorkerProfile?: boolean }) {
    return this.usersService.updateProfile(id, data);
  }

  @Patch(':id/fcm-token')
  async updateFcmToken(@Param('id') id: string, @Body('token') token: string) {
    if (!token) throw new Error('FCM token is required');
    return this.usersService.updateFcmToken(id, token);
  }


  @Patch('skill/:skillId/status')
  async updateSkillStatus(@Param('skillId') skillId: string, @Body('status') status: SkillApprovalStatus) {
    return this.talentService.updateSkillStatus(skillId, status);
  }

  @Patch(':id/status')
  async updateStatus(@Param('id') id: string, @Body('status') status: UserApprovalStatus) {
    return this.usersService.updateApprovalStatus(id, status);
  }

  @Patch(':id/verify')
  async verifyUser(@Param('id') id: string, @Body('isVerified') isVerified: boolean) {
    return this.usersService.updateVerification(id, isVerified);
  }
}
