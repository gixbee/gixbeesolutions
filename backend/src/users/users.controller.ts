import {
  Controller,
  Get,
  Patch,
  Param,
  Query,
  Body,
  Req,
  UseGuards,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { UsersService } from './users.service';
import { TalentService } from '../talent/talent.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { UpdateUserProfileDto } from './dto/update-profile.dto';
import {
  UpdateFcmTokenDto,
  UpdateSkillStatusDto,
  UpdateUserStatusDto,
  VerifyUserDto,
} from './dto/user-admin.dto';
import { parsePagination } from '../common/pagination';
import { UserRole } from './user.entity';

/** Portal session from `/auth/admin-login` — not a mobile JWT with orphan `role=ADMIN`. */
function isPortalAdmin(req: {
  user?: { role?: string; staffRole?: string };
}): boolean {
  return req.user?.role === UserRole.ADMIN && !!req.user?.staffRole;
}

function assertSelfOrPortalAdmin(
  req: {
    user: { userId: string; role?: string; staffRole?: string };
  },
  id: string,
  message: string,
): void {
  if (req.user.userId !== id && !isPortalAdmin(req)) {
    throw new ForbiddenException(message);
  }
}

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
  @RequireAdminPage('dashboard', 'users')
  async getSummary() {
    return this.usersService.getSystemSummary();
  }

  @Get()
  @UseGuards(AdminGuard)
  @RequireAdminPage('users')
  async getAllUsers(
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const p = parsePagination(page, limit);
    return this.usersService.findAll(p.page, p.limit);
  }

  // Registered BEFORE @Get(':id') so the static "search" segment isn't captured
  // as an :id. Name/phone lookup for the operator picker (P106) — pass ?q= and
  // an optional ?limit=. Empty q returns [].
  @Get('search')
  async searchUsers(
    @Query('q') q: string,
    @Query('limit') limit?: string,
    @Req() req?: any,
  ) {
    const parsed = limit !== undefined ? parseInt(limit, 10) : 20;
    const n = Number.isFinite(parsed) ? parsed : 20;
    const includePhone = isPortalAdmin(req ?? {});
    return this.usersService.searchUsers(q ?? '', n, { includePhone });
  }

  @Get(':id')
  async getUser(@Param('id') id: string, @Req() req: any) {
    assertSelfOrPortalAdmin(
      req,
      id,
      'You can only view your own profile',
    );
    return this.usersService.findById(id);
  }

  @Get(':id/stats')
  async getUserStats(@Param('id') id: string, @Req() req: any) {
    assertSelfOrPortalAdmin(
      req,
      id,
      'You can only view your own stats',
    );
    return this.usersService.getUserStats(id);
  }

  @Patch(':id')
  async updateProfile(
    @Param('id') id: string,
    @Req() req: any,
    @Body() data: UpdateUserProfileDto,
  ) {
    // Self-or-portal-admin: mobile JWTs must not edit other users even if
    // role=ADMIN was escalated in DB before ARCH-001 shipped.
    assertSelfOrPortalAdmin(
      req,
      id,
      'You can only update your own profile',
    );
    const portalAdmin = isPortalAdmin(req);
    if (
      !portalAdmin &&
      (data.role !== undefined || data.hasWorkerProfile !== undefined)
    ) {
      throw new ForbiddenException(
        'Only admins can change role or worker profile',
      );
    }
    return this.usersService.updateProfile(id, data, {
      allowPrivilegedFields: portalAdmin,
    });
  }

  @Patch(':id/fcm-token')
  async updateFcmToken(
    @Param('id') id: string,
    @Req() req: any,
    @Body() body: UpdateFcmTokenDto,
  ) {
    // SECURITY FIX: was trusting the URL id — any user could overwrite another
    // user's push token and hijack their notifications (incl. OTP pushes).
    if (req.user.userId !== id && !isPortalAdmin(req)) {
      throw new ForbiddenException('You can only update your own device token');
    }
    if (!body.token) throw new BadRequestException('FCM token is required');
    return this.usersService.updateFcmToken(id, body.token);
  }

  @Patch('skill/:skillId/status')
  @UseGuards(AdminGuard)
  @RequireAdminPage('users', 'verifications')
  async updateSkillStatus(
    @Param('skillId') skillId: string,
    @Body() body: UpdateSkillStatusDto,
  ) {
    return this.talentService.updateSkillStatus(skillId, body.status);
  }

  @Patch(':id/status')
  @UseGuards(AdminGuard)
  @RequireAdminPage('users')
  async updateStatus(
    @Param('id') id: string,
    @Body() body: UpdateUserStatusDto,
  ) {
    return this.usersService.updateApprovalStatus(id, body.status);
  }

  @Patch(':id/verify')
  @UseGuards(AdminGuard)
  @RequireAdminPage('users')
  async verifyUser(@Param('id') id: string, @Body() body: VerifyUserDto) {
    return this.usersService.updateVerification(id, body.isVerified);
  }
}
