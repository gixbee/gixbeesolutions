import { Controller, Get, Patch, Param, Query, Body, Req, UseGuards, ForbiddenException, BadRequestException } from '@nestjs/common';
import { UsersService } from './users.service';
import { TalentService } from '../talent/talent.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { UpdateUserProfileDto } from './dto/update-profile.dto';
import {
  UpdateFcmTokenDto,
  UpdateSkillStatusDto,
  UpdateUserStatusDto,
  VerifyUserDto,
} from './dto/user-admin.dto';

@Controller('admin-user-list')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(
    private readonly usersService: UsersService,
    private readonly talentService: TalentService,
  ) {}

  // Portal-only routes carry AdminGuard; routes the mobile app legitimately
  // calls (search, :id/stats, PATCH :id for OWN profile, fcm-token) stay
  // user-accessible — PATCH :id now enforces self-or-admin instead of
  // trusting the URL id (was an auth bypass).
  @Get('summary')
  @UseGuards(AdminGuard)
  async getSummary() {
    return this.usersService.getSystemSummary();
  }

  @Get()
  @UseGuards(AdminGuard)
  async getAllUsers() {
    return this.usersService.findAll();
  }

  // Registered BEFORE @Get(':id') so the static "search" segment isn't captured
  // as an :id. Name/phone lookup for the operator picker (P106) — pass ?q= and
  // an optional ?limit=. Empty q returns [].
  @Get('search')
  async searchUsers(@Query('q') q: string, @Query('limit') limit?: string) {
    const parsed = limit !== undefined ? parseInt(limit, 10) : 20;
    const n = Number.isFinite(parsed) ? parsed : 20;
    return this.usersService.searchUsers(q ?? '', n);
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
  async updateProfile(
    @Param('id') id: string,
    @Req() req: any,
    @Body() data: UpdateUserProfileDto,
  ) {
    // Self-or-admin: a user may only edit their OWN profile.
    if (req.user.userId !== id && req.user.role !== 'ADMIN') {
      throw new ForbiddenException('You can only update your own profile');
    }
    return this.usersService.updateProfile(id, data);
  }

  @Patch(':id/fcm-token')
  async updateFcmToken(@Param('id') id: string, @Req() req: any, @Body() body: UpdateFcmTokenDto) {
    // SECURITY FIX: was trusting the URL id — any user could overwrite another
    // user's push token and hijack their notifications (incl. OTP pushes).
    if (req.user.userId !== id && req.user.role !== 'ADMIN') {
      throw new ForbiddenException('You can only update your own device token');
    }
    if (!body.token) throw new BadRequestException('FCM token is required');
    return this.usersService.updateFcmToken(id, body.token);
  }


  @Patch('skill/:skillId/status')
  @UseGuards(AdminGuard)
  async updateSkillStatus(@Param('skillId') skillId: string, @Body() body: UpdateSkillStatusDto) {
    return this.talentService.updateSkillStatus(skillId, body.status);
  }

  @Patch(':id/status')
  @UseGuards(AdminGuard)
  async updateStatus(@Param('id') id: string, @Body() body: UpdateUserStatusDto) {
    return this.usersService.updateApprovalStatus(id, body.status);
  }

  @Patch(':id/verify')
  @UseGuards(AdminGuard)
  async verifyUser(@Param('id') id: string, @Body() body: VerifyUserDto) {
    return this.usersService.updateVerification(id, body.isVerified);
  }
}
