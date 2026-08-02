import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { WorkerProfile, VerificationStatus } from './worker-profile.entity';
import { WorkerStrikeType } from './worker-strike.entity';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { User, UserApprovalStatus } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
import { WorkerAvailabilityService } from './worker-availability.service';
import { WorkerGoLiveService } from './worker-golive.service';
import { WorkerStrikeService } from './worker-strike.service';
import {
  WorkerDto,
  MAX_DISPATCH_RADIUS_KM,
  DEFAULT_SERVICE_RADIUS_KM,
  MAX_NEARBY_CANDIDATES,
  MAX_BROADCAST_FANOUT,
  SUSPENSION_STRIKE_THRESHOLD,
  WALLET_PAYMENTS_ENABLED,
  REBROADCAST_RADIUS_STRETCH,
  WORKERS_LIST_CACHE_KEY,
} from './worker.shared';

export type { WorkerDto };
export {
  MAX_DISPATCH_RADIUS_KM,
  DEFAULT_SERVICE_RADIUS_KM,
  MAX_NEARBY_CANDIDATES,
  MAX_BROADCAST_FANOUT,
  SUSPENSION_STRIKE_THRESHOLD,
  WALLET_PAYMENTS_ENABLED,
  REBROADCAST_RADIUS_STRETCH,
};

@Injectable()
export class WorkersService {
  private readonly logger = new Logger(WorkersService.name);

  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(TalentProfile)
    private readonly talentRepository: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepository: Repository<ProfessionalSkill>,
    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
    private readonly redisService: RedisService,
    private readonly workerAvailabilityService: WorkerAvailabilityService,
    private readonly workerGoLiveService: WorkerGoLiveService,
    private readonly workerStrikeService: WorkerStrikeService,
  ) {}

  async invalidateWorkerListCache(): Promise<void> {
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
  }


  async getAll(requesterId?: string): Promise<WorkerDto[]> {
    // AUDIT FIX (uncached feed + N+1): the full directory is built once and
    // cached for 60s. The requester-specific bit (hide yourself) is applied
    // AFTER the cache read, so one cache entry serves every user.
    const cached = await this.redisService.get(WORKERS_LIST_CACHE_KEY);
    if (cached) {
      const all = JSON.parse(cached) as WorkerDto[];
      return requesterId ? all.filter((w) => w.id !== requesterId) : all;
    }

    // 1. Fetch from WorkerProfile
    const profiles = await this.workersRepository.find({
      relations: ['user'],
    });

    // 2. Fetch from TalentProfile
    const talentProfiles = await this.talentRepository.find({
      relations: ['user', 'professionalSkills'],
    });

    // Eligible profiles only (available + approved). NOTE: requesterId is NOT
    // applied here — the cached list is shared; self-exclusion happens below.
    const eligible = profiles.filter(
      (p) =>
        p.user?.isAvailableForWork !== false &&
        (!p.user || p.user.approvalStatus === UserApprovalStatus.APPROVED),
    );
    const eligibleTalent = talentProfiles.filter(
      (p) =>
        p.user?.isAvailableForWork !== false &&
        (!p.user || p.user.approvalStatus === UserApprovalStatus.APPROVED),
    );

    // AUDIT FIX (N+1): resolve every worker's busy/available status in
    // parallel instead of awaiting one at a time.
    const [statuses, talentStatuses] = await Promise.all([
      Promise.all(
        eligible.map((p) => this.workerAvailabilityService.getWorkerStatus(p.user?.id || p.id)),
      ),
      Promise.all(
        eligibleTalent.map((p) => this.workerAvailabilityService.getWorkerStatus(p.user?.id || p.id)),
      ),
    ]);

    const allWorkerDtos: WorkerDto[] = [
      ...eligible.map((p, i) => this.workerAvailabilityService.mapToDto(p, statuses[i])),
      ...eligibleTalent.map((p, i) =>
        this.workerAvailabilityService.mapTalentToDto(p, talentStatuses[i]),
      ),
    ];

    // 3. Deduplicate by user ID
    const uniqueWorkersMap = new Map<string, WorkerDto>();
    for (const w of allWorkerDtos) {
      if (!uniqueWorkersMap.has(w.id)) {
        uniqueWorkersMap.set(w.id, w);
      }
    }
    const all = Array.from(uniqueWorkersMap.values());

    // Cache the shared directory for 60s; writes call invalidateWorkerListCache().
    await this.redisService
      .set(WORKERS_LIST_CACHE_KEY, JSON.stringify(all), 60)
      .catch(() => {});

    return requesterId ? all.filter((w) => w.id !== requesterId) : all;
  }

  async getById(id: string): Promise<WorkerDto> {
    const profile = await this.workersRepository.findOne({
      where: { id },
      relations: ['user'],
    });

    if (!profile) {
      const userProfile = await this.workersRepository.findOne({
        where: { user: { id } },
        relations: ['user'],
      });
      if (!userProfile) {
        throw new NotFoundException(`Worker with ID ${id} not found`);
      }
      const status = await this.workerAvailabilityService.getWorkerStatus(
        userProfile.user?.id || userProfile.id,
      );
      return this.workerAvailabilityService.mapToDto(userProfile, status);
    }

    const status = await this.workerAvailabilityService.getWorkerStatus(profile.user?.id || profile.id);
    return this.workerAvailabilityService.mapToDto(profile, status);
  }

  // ── Availability (delegates) ───────────────────────────────────────────

  setWorkerStatus(userId: string, status: 'available' | 'busy') {
    return this.workerAvailabilityService.setWorkerStatus(userId, status);
  }

  getNearby(
    requesterId: string,
    skill: string,
    lat: number,
    lng: number,
    radiusStretch = 1,
  ) {
    return this.workerAvailabilityService.getNearby(
      requesterId,
      skill,
      lat,
      lng,
      radiusStretch,
    );
  }

  getNearbyCounts(lat: number, lng: number) {
    return this.workerAvailabilityService.getNearbyCounts(lat, lng);
  }

  // ── Go-live (delegates) ────────────────────────────────────────────────

  toggleGoLive(
    id: string,
    coords?: { lat?: number; lng?: number; active?: boolean },
  ) {
    return this.workerGoLiveService.toggleGoLive(id, coords);
  }

  periodicJobsPerPayment() {
    return this.workerGoLiveService.periodicJobsPerPayment();
  }

  recordCompletedJobForPeriod(userId: string) {
    return this.workerGoLiveService.recordCompletedJobForPeriod(userId);
  }

  forceOffline(userId: string) {
    return this.workerGoLiveService.forceOffline(userId);
  }

  markPeriodFeePaid(userId: string) {
    return this.workerGoLiveService.markPeriodFeePaid(userId);
  }

  payPeriodFee(userId: string) {
    return this.workerGoLiveService.payPeriodFee(userId);
  }

  updateMyLocation(
    userId: string,
    lat: number,
    lng: number,
  ) {
    return this.workerGoLiveService.updateMyLocation(userId, lat, lng);
  }

  setActiveSkills(userId: string, skills: string[]) {
    return this.workerGoLiveService.setActiveSkills(userId, skills);
  }

  getDashboard(userId: string) {
    return this.workerGoLiveService.getDashboard(userId);
  }

  async refreshWorkerSnapshot(userId: string): Promise<void> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });
    if (!profile) return;
    const status = await this.workerAvailabilityService.getWorkerStatus(userId);
    await this.redisService.cacheWorkerSnapshot(
      userId,
      this.workerAvailabilityService.mapToDto(profile, status),
    );
    await this.invalidateWorkerListCache();
  }


  // ── Strikes (delegates) ────────────────────────────────────────────────

  addStrike(userId: string) {
    return this.workerStrikeService.addStrike(userId);
  }

  recordStrike(
    userId: string,
    opts: { type: WorkerStrikeType; reason: string; bookingId?: string },
  ) {
    return this.workerStrikeService.recordStrike(userId, opts);
  }

  getMyStrikes(userId: string) {
    return this.workerStrikeService.getMyStrikes(userId);
  }

  appealStrike(userId: string, strikeId: string, message: string) {
    return this.workerStrikeService.appealStrike(userId, strikeId, message);
  }

  adminListStrikes(status?: string) {
    return this.workerStrikeService.adminListStrikes(status);
  }

  adminResolveStrike(
    strikeId: string,
    overturn: boolean,
    note?: string,
  ) {
    return this.workerStrikeService.adminResolveStrike(strikeId, overturn, note);
  }

  async createProfile(
    userId: string,
    data: {
      skills: string[];
      hourlyRate: number;
      bio?: string;
      title?: string;
    },
  ): Promise<WorkerProfile> {
    const existing = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });

    const tradeSkills = await this.workerGoLiveService.normalizeTradeSkills(data.skills || []);

    let saved: WorkerProfile;
    if (existing) {
      // Upsert: replace with trade-level skills (not sub-skill noise).
      existing.skills = tradeSkills;
      existing.hourlyRate = data.hourlyRate;
      if (data.bio !== undefined) existing.bio = data.bio;
      if (data.title !== undefined) existing.title = data.title;
      // Drop active entries that are no longer trades.
      existing.activeSkills = (existing.activeSkills || []).filter((s) =>
        tradeSkills.includes(s),
      );
      saved = await this.workersRepository.save(existing);
    } else {
      const profile = this.workersRepository.create({
        user: { id: userId } as any,
        skills: tradeSkills,
        hourlyRate: data.hourlyRate,
        bio: data.bio,
        title: data.title,
        isActive: false,
        isFirstJobDone: false,
        verificationStatus: 'PENDING' as any,
      });
      saved = await this.workersRepository.save(profile);
    }

    // Mark the account as a worker so GET /auth/profile reports
    // hasWorkerProfile=true on the next login and the app routes straight to
    // Go Live instead of the onboarding wizard. Also heals accounts that
    // registered before this fix (their re-submit lands in the upsert branch).
    await this.usersRepository.update(userId, { hasWorkerProfile: true });
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});

    return saved;
  }

  /// The authed user's own worker profile for GET /workers/me.
  /// `{ registered: false }` when none exists — the app uses this to decide
  /// wizard vs Go Live and to show verificationStatus without re-verifying.
  async getMyProfile(userId: string): Promise<any> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) {
      return { registered: false };
    }
    return {
      registered: true,
      id: profile.id,
      skills: profile.skills ?? [],
      hourlyRate: profile.hourlyRate,
      bio: profile.bio,
      title: profile.title,
      isActive: profile.isActive,
      verificationStatus: profile.verificationStatus,
      isFirstJobDone: profile.isFirstJobDone,
      languages: profile.languages ?? [],
      serviceRadiusKm: profile.serviceRadiusKm ?? DEFAULT_SERVICE_RADIUS_KM,
    };
  }

  // ── Admin: worker verification queue ──────────────────────────────────────

  /// All PENDING worker profiles with the applicant's identity + uploaded
  /// documents (photo/certificates live on the TalentProfile), for the admin
  /// portal's verification queue.
  async getVerificationQueue(status?: string): Promise<any[]> {
    const where: any = {};
    if (status) where.verificationStatus = status as any;
    const profiles = await this.workersRepository.find({
      where,
      relations: ['user'],
      order: { id: 'DESC' },
    });
    if (profiles.length === 0) return [];

    // AUDIT FIX (N+1): the talent profile (photo + certificates) used to be
    // fetched with one query PER pending worker. Now it's a single IN query,
    // indexed by userId for the join below.
    const userIds = profiles.map((p) => p.user?.id).filter(Boolean);
    const talents = userIds.length
      ? await this.talentRepository.find({
          where: { user: { id: In(userIds) } } as any,
          relations: ['user'],
        })
      : [];
    const talentByUser = new Map<string, TalentProfile>();
    for (const t of talents) {
      if (t.user?.id) talentByUser.set(t.user.id, t);
    }

    return profiles.map((p) => {
      const talent = p.user?.id ? talentByUser.get(p.user.id) : undefined;
      return {
        userId: p.user?.id,
        name: p.user?.name,
        phone: p.user?.phoneNumber,
        skills: p.skills ?? [],
        hourlyRate: p.hourlyRate,
        bio: p.bio,
        verificationStatus: p.verificationStatus,
        languages: p.languages ?? [],
        photoUrl: talent?.photoUrl ?? null,
        certificates: talent?.certificates ?? [],
      };
    });
  }

  /// Approve/reject a worker's verification. Approval also flips the user's
  /// verified flags so ranking and trust badges pick it up.
  async setVerificationStatus(
    userId: string,
    status: 'VERIFIED' | 'REJECTED',
  ): Promise<{ userId: string; verificationStatus: string }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) throw new NotFoundException('Worker profile not found');
    profile.verificationStatus = status as any;
    await this.workersRepository.save(profile);
    if (status === 'VERIFIED') {
      await this.usersRepository.update(userId, {
        isVerified: true,
        hasWorkerProfile: true,
      } as any);
    }
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
    return { userId, verificationStatus: status };
  }

  /// v126 language matching — the pro sets the languages they speak.
  /// Refreshes the cached worker snapshot so broadcast fan-outs see the
  /// change immediately.
  async setLanguages(
    userId: string,
    languages: string[],
  ): Promise<{ languages: string[] }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });
    if (!profile) throw new NotFoundException('Worker profile not found');
    profile.languages = languages;
    await this.workersRepository.save(profile);
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
    try {
      const status = await this.workerAvailabilityService.getWorkerStatus(userId);
      await this.redisService.cacheWorkerSnapshot(
        userId,
        this.workerAvailabilityService.mapToDto(profile, status),
      );
    } catch (e) {
      console.error('[SetLanguages] snapshot refresh failed:', e);
    }
    return { languages };
  }

  /// The pro sets how far they'll travel for instant jobs. Clamped to
  /// [1, MAX_DISPATCH_RADIUS_KM] server-side — never trust the client.
  /// Refreshes the cached snapshot so the very next broadcast honours it.
  async setServiceRadius(
    userId: string,
    radiusKm: number,
  ): Promise<{ serviceRadiusKm: number }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });
    if (!profile) throw new NotFoundException('Worker profile not found');

    const clamped = Math.max(
      1,
      Math.min(Math.round(radiusKm), MAX_DISPATCH_RADIUS_KM),
    );
    profile.serviceRadiusKm = clamped;
    await this.workersRepository.save(profile);
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
    try {
      const status = await this.workerAvailabilityService.getWorkerStatus(userId);
      await this.redisService.cacheWorkerSnapshot(
        userId,
        this.workerAvailabilityService.mapToDto(profile, status),
      );
    } catch (e) {
      console.error('[SetServiceRadius] snapshot refresh failed:', e);
    }
    return { serviceRadiusKm: clamped };
  }

  // DEFECT-007: Update hourly rate with 2/day rate limit
  async updateHourlyRate(
    userId: string,
    newRate: number,
  ): Promise<{ hourlyRate: number }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) throw new NotFoundException('Worker profile not found');

    const todayStr = this.workerGoLiveService.istToday(); // IST — same midnight-rollover fix as go-live
    if (profile.rateUpdateDate !== todayStr) {
      profile.rateUpdateDate = todayStr;
      profile.rateUpdateCountToday = 0;
    }
    if (profile.rateUpdateCountToday >= 2) {
      throw new BadRequestException(
        'Hourly rate can only be updated twice per day.',
      );
    }
    profile.hourlyRate = newRate;
    profile.rateUpdateCountToday += 1;
    await this.workersRepository.save(profile);
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
    return { hourlyRate: newRate };
  }

  // ── Worker Packages ────────────────────────────────────────────────────────

  async getWorkerPackages(workerId: string): Promise<any[]> {
    const worker = await this.getById(workerId);
    const rate = worker.hourly_rate || 50;

    // Try to find rateChart from the worker's professional skills
    const profile = await this.talentRepository.findOne({
      where: { user: { id: workerId } } as any,
    });

    if (profile) {
      const skills = await this.skillRepository.find({
        where: { talentProfile: { id: profile.id } },
      });

      // Check if any skill has a rateChart with custom package pricing
      const skillWithChart = skills.find(
        (s) => s.rateChart && Object.keys(s.rateChart).length > 0,
      );

      if (skillWithChart && skillWithChart.rateChart) {
        const chart = skillWithChart.rateChart;
        const packages: any[] = [];

        // Map rateChart keys to package definitions
        if (chart['quickFix'] || chart['1hr']) {
          packages.push({
            name: 'Quick Fix',
            description: `1 hour of focused ${skillWithChart.name} work`,
            duration: '1 hr',
            price: chart['quickFix'] || chart['1hr'] || rate,
            isPopular: false,
            includes: ['1 task', 'Basic tools', 'Arrival OTP verified'],
          });
        }
        if (chart['halfDay'] || chart['4hr']) {
          packages.push({
            name: 'Half Day',
            description: `Extended ${skillWithChart.name} session for bigger jobs`,
            duration: '4 hrs',
            price: chart['halfDay'] || chart['4hr'],
            isPopular: true,
            includes: [
              'Up to 3 tasks',
              'All tools included',
              'Report on completion',
            ],
          });
        }
        if (chart['fullDay'] || chart['8hr']) {
          packages.push({
            name: 'Full Day',
            description: `Full day ${skillWithChart.name} engagement`,
            duration: '8 hrs',
            price: chart['fullDay'] || chart['8hr'],
            isPopular: false,
            includes: [
              'Unlimited tasks',
              'Materials advice',
              'Priority rebooking',
            ],
          });
        }

        if (packages.length > 0) return packages;
      }
    }

    // Fallback: multiplier-based packages
    return [
      {
        name: 'Quick Fix',
        description: '1 hour of focused work on a single task',
        duration: '1 hr',
        price: rate,
        isPopular: false,
        includes: ['1 task', 'Basic tools', 'Arrival OTP verified'],
      },
      {
        name: 'Half Day',
        description: 'Standard 4-hour block for moderate sized projects',
        duration: '4 hrs',
        price: Math.round(rate * 3.5),
        isPopular: true,
        includes: [
          'Up to 3 tasks',
          'All tools included',
          'Report on completion',
        ],
      },
      {
        name: 'Full Day',
        description: 'Comprehensive 8-hour dedication to your needs',
        duration: '8 hrs',
        price: Math.round(rate * 6.0),
        isPopular: false,
        includes: ['Unlimited tasks', 'Materials advice', 'Priority rebooking'],
      },
    ];
  }
}

