import {
  Controller,
  Get,
  Post,
  Patch,
  Param,
  Query,
  Body,
  Req,
  UseGuards,
} from '@nestjs/common';
import { WorkersService } from './workers.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import {
  SetActiveSkillsDto,
  RegisterWorkerDto,
  UpdateRateDto,
  UpdateLanguagesDto,
  SetWorkerVerificationDto,
  UpdateServiceRadiusDto,
  LiveToggleDto,
  UpdateLocationDto,
  AppealStrikeDto,
  ResolveStrikeDto,
} from './dto/workers.dto';

@Controller('workers')
@UseGuards(JwtAuthGuard)
export class WorkersController {
  constructor(private readonly workersService: WorkersService) {}

  @Get()
  async getAll(@Req() req) {
    return this.workersService.getAll(req.user.userId);
  }

  // DEFECT-008: Nearby worker search with skill + location filtering
  @Get('nearby')
  async getNearby(
    @Req() req,
    @Query('skill') skill: string,
    @Query('lat') lat: string,
    @Query('lng') lng: string,
  ) {
    return this.workersService.getNearby(
      req.user.userId,
      skill,
      parseFloat(lat),
      parseFloat(lng),
    );
  }

  /// Approximate live-pro counts per trade around the given point — powers
  /// the customer service-selection grid ("~8 live nearby"). Values are
  /// upper-bound approximations (pre language/travel-radius filters) and
  /// cached ~45s server-side; clients must render them with "~".
  @Get('nearby-counts')
  async getNearbyCounts(@Query('lat') lat: string, @Query('lng') lng: string) {
    return this.workersService.getNearbyCounts(
      parseFloat(lat),
      parseFloat(lng),
    );
  }

  /// Go-Live dashboard for the authed worker: skills + active-skill toggles,
  /// live state, and an earnings summary (total / today / this week + recent
  /// completed jobs). Declared before ':id' so the static segment wins.
  @Get('me/dashboard')
  async getMyDashboard(@Req() req) {
    return this.workersService.getDashboard(req.user.userId);
  }

  /// The authed user's OWN worker profile, or `{ registered: false }` when
  /// none exists. Lets the app decide between the Earn Hourly onboarding
  /// wizard and the Go Live dashboard without re-running registration, and
  /// exposes verificationStatus so the verification step isn't re-asked.
  /// Declared before ':id' so the static segment wins.
  @Get('me')
  async getMe(@Req() req) {
    return this.workersService.getMyProfile(req.user.userId);
  }

  // ── Admin: verification queue (portal only) ──────────────────────────────
  // Declared before ':id' so the static segment wins.
  @Get('admin/verification-queue')
  @UseGuards(AdminGuard)
  @RequireAdminPage('verifications')
  async getVerificationQueue(@Query('status') status?: string) {
    return this.workersService.getVerificationQueue(status || undefined);
  }

  @Patch('admin/:userId/verification')
  @UseGuards(AdminGuard)
  @RequireAdminPage('verifications')
  async setVerification(
    @Param('userId') userId: string,
    @Body() body: SetWorkerVerificationDto,
  ) {
    return this.workersService.setVerificationStatus(userId, body.status);
  }

  /// Fair-penalty ledger: the worker's own strikes with reasons + appeal
  /// state (Profile → Strikes). Declared before ':id' so the static wins.
  @Get('me/strikes')
  async getMyStrikes(@Req() req) {
    return this.workersService.getMyStrikes(req.user.userId);
  }

  /// Worker appeals one of their own strikes (one appeal per strike).
  @Post('me/strikes/:strikeId/appeal')
  async appealStrike(
    @Req() req,
    @Param('strikeId') strikeId: string,
    @Body() body: AppealStrikeDto,
  ) {
    return this.workersService.appealStrike(
      req.user.userId,
      strikeId,
      body.message,
    );
  }

  /// Admin: strike queue — ?status=APPEALED shows appeals awaiting review.
  @Get('admin/strikes')
  @UseGuards(AdminGuard)
  @RequireAdminPage('disputes')
  async adminListStrikes(@Query('status') status?: string) {
    return this.workersService.adminListStrikes(status || undefined);
  }

  /// Admin: overturn (removes from the count, can lift suspension) or uphold.
  @Patch('admin/strikes/:strikeId/resolve')
  @UseGuards(AdminGuard)
  @RequireAdminPage('disputes')
  async adminResolveStrike(
    @Param('strikeId') strikeId: string,
    @Body() body: ResolveStrikeDto,
  ) {
    return this.workersService.adminResolveStrike(
      strikeId,
      body.overturn,
      body.note,
    );
  }

  /// v126 language matching: the languages this pro speaks. Going live
  /// requires at least one. Broadcasts with a language preference only
  /// notify overlapping pros (legacy live pros with none still match).
  @Patch('me/languages')
  async setLanguages(@Req() req, @Body() body: UpdateLanguagesDto) {
    return this.workersService.setLanguages(
      req.user.userId,
      body.languages ?? [],
    );
  }

  /// Service area: how far the pro is willing to travel for instant jobs.
  /// Jobs outside this radius are never broadcast to them. Server clamps to
  /// 1..MAX_DISPATCH_RADIUS_KM.
  @Patch('me/service-radius')
  async setServiceRadius(@Req() req, @Body() body: UpdateServiceRadiusDto) {
    return this.workersService.setServiceRadius(
      req.user.userId,
      body.serviceRadiusKm,
    );
  }

  /// Per-service activation: which of the worker's skills accept instant jobs.
  @Patch('me/active-skills')
  async setActiveSkills(@Req() req, @Body() body: SetActiveSkillsDto) {
    return this.workersService.setActiveSkills(
      req.user.userId,
      body?.skills ?? [],
    );
  }

  /// Periodic fee plan ("N jobs, then pay"): pay the period fee to unlock
  /// the next batch of included jobs. Wallet-charged; resets the counter.
  /// Master Entries: go_live_jobs_per_payment / go_live_period_fee.
  @Post('me/pay-period-fee')
  async payPeriodFee(@Req() req) {
    return this.workersService.payPeriodFee(req.user.userId);
  }

  @Get(':id')
  async getById(@Param('id') id: string) {
    return this.workersService.getById(id);
  }

  // DEFECT-004 FIX: Use JWT userId instead of URL param to prevent auth bypass
  @Post('live-toggle')
  async toggleGoLive(@Req() req, @Body() body: LiveToggleDto) {
    return this.workersService.toggleGoLive(req.user.userId, {
      lat: body?.lat,
      lng: body?.lng,
      active: body?.active,
    });
  }

  /// Persist GPS for Instant Help matching while the worker is live.
  @Patch('me/location')
  async updateMyLocation(@Req() req, @Body() body: UpdateLocationDto) {
    return this.workersService.updateMyLocation(
      req.user.userId,
      body.lat,
      body.lng,
    );
  }

  // DEFECT-006: Worker registration endpoint
  @Post('register')
  async register(@Req() req, @Body() body: RegisterWorkerDto) {
    return this.workersService.createProfile(req.user.userId, body);
  }

  // DEFECT-007: Hourly rate update with 2/day rate limiting
  @Patch('rate')
  async updateRate(@Req() req, @Body() body: UpdateRateDto) {
    return this.workersService.updateHourlyRate(
      req.user.userId,
      body.hourlyRate,
    );
  }

  @Get(':id/packages')
  async getPackages(@Param('id') id: string) {
    return this.workersService.getWorkerPackages(id);
  }
}
