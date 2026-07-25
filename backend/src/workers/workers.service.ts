import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { WorkerProfile } from './worker-profile.entity';
import { WalletsService } from '../wallets/wallets.service';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { User, UserApprovalStatus } from '../users/user.entity';
import { Booking, BookingStatus } from '../bookings/booking.entity';
import { RedisService } from '../redis/redis.service';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { MasterEntryType } from '../master-entries/master-entry.entity';

// Worker data matching the Flutter Worker model's expectations exactly
export interface WorkerDto {
  id: string;
  name: string;
  title: string;
  bio: string;
  image_url: string;
  rating: number;
  completed_jobs: number;
  review_count: number;
  is_featured: boolean;
  hourly_rate: number;
  skills: string[];
  availability_tags: string[];
  primary_type: string;
  is_active?: boolean;
  status: 'available' | 'busy';
  /** Straight-line distance from the requester in km, rounded to 1 dp.
   *  Only populated by the geo-aware `getNearby` path; absent on the plain
   *  `/workers` list (which has no requester location). */
  distance_km?: number;

  /** Languages the pro speaks (v126 language matching). Absent/empty =
   *  unknown — treated leniently by the broadcast fan-out. */
  languages?: string[];

  /** How far this pro is willing to travel, in km. The dispatch fan-out
   *  only notifies them when distance_km <= this. Absent = legacy profile,
   *  treated as DEFAULT_SERVICE_RADIUS_KM. */
  service_radius_km?: number;
}

/**
 * Hard ceiling on how far any pro can be dispatched (also the GEOSEARCH
 * pre-filter). A pro's own radius is clamped to this.
 *
 * Instant Help is city-scoped via this geo radius — User/WorkerProfile have
 * no cityId yet; City exists only for the app location picker. Do not invent
 * a city schema migration for dispatch.
 */
export const MAX_DISPATCH_RADIUS_KM = 50;

/** Applied to legacy profiles that never set a radius. */
export const DEFAULT_SERVICE_RADIUS_KM = 10;

/**
 * Cap on candidates that proceed to snapshot/status resolution after the
 * distance filter. Prevents unbounded Redis/DB work when the geo index is
 * cold and the skill set is huge (~1k live workers).
 */
export const MAX_NEARBY_CANDIDATES = 40;

/**
 * Hard cap on Instant Help broadcast fan-out (pending queue + FCM/socket).
 * Applied after language filter + nearest/best sort.
 */
export const MAX_BROADCAST_FANOUT = 15;

@Injectable()
export class WorkersService {
  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(TalentProfile)
    private readonly talentRepository: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepository: Repository<ProfessionalSkill>,
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
    private readonly walletsService: WalletsService,
    private readonly redisService: RedisService,
    private readonly masterEntriesService: MasterEntriesService,
  ) {}

  private async getWorkerStatus(userId: string): Promise<'available' | 'busy'> {
    // 1. Try Redis cache first
    const cachedStatus = await this.redisService.get(`worker:status:${userId}`);
    if (cachedStatus === 'busy') return 'busy';
    if (cachedStatus === 'available') return 'available';

    // 2. Fallback to DB query
    const activeBooking = await this.bookingsRepository.findOne({
      where: [
        { operator: { id: userId }, status: BookingStatus.ACTIVE },
        { operator: { id: userId }, status: BookingStatus.ACCEPTED },
        { operator: { id: userId }, status: BookingStatus.CONFIRMED },
      ],
    });
    
    const status = activeBooking ? 'busy' : 'available';
    // 3. Update cache for next time
    await this.redisService.set(`worker:status:${userId}`, status, 3600); // 1hr TTL
    return status;
  }

  /**
   * Specifically used to force-sync status in Redis when booking events happen
   */
  async setWorkerStatus(userId: string, status: 'available' | 'busy'): Promise<void> {
    await this.redisService.set(`worker:status:${userId}`, status, 3600);
  }

  /**
   * Helper mapper to convert from TypeORM entity to Flutter's DTO interface
   * This handles the shape mismatch from DB structure to API payload.
   */
  private  mapToDto(profile: WorkerProfile, status: 'available' | 'busy' = 'available'): WorkerDto {
    return {
      id: profile.user?.id || profile.id, // Using user ID externally if available
      name: profile.user?.name || 'Unknown Worker',
      title: profile.title || 'Professional Services',
      bio: profile.bio || '',
      image_url: profile.user?.profileImageUrl || 'https://i.pravatar.cc/150',
      rating: Number(profile.rating),
      completed_jobs: profile.completedJobs,
      review_count: profile.reviewCount,
      is_featured: false, // Could be logic driven
      hourly_rate: Number(profile.hourlyRate),
      skills: profile.skills || [],
      availability_tags: profile.availabilityTags || [],
      primary_type: 'manual', // Can be dynamically deduced based on skills
      is_active: profile.isActive,
      status: status,
      languages: profile.languages || [],
      service_radius_km: profile.serviceRadiusKm ?? DEFAULT_SERVICE_RADIUS_KM,
    };
  }

  private mapTalentToDto(profile: TalentProfile, status: 'available' | 'busy' = 'available'): WorkerDto {
    const primarySkill = profile.professionalSkills?.[0];
    return {
      id: profile.user?.id || profile.id,
      name: profile.user?.name || 'Unknown Professional',
      title: primarySkill ? `${primarySkill.name} Expert` : 'Professional Services',
      bio: profile.experience || '',
      image_url: profile.user?.profileImageUrl || 'https://i.pravatar.cc/150',
      rating: 5.0, // Default for new pros
      completed_jobs: 0,
      review_count: 0,
      is_featured: false,
      hourly_rate: primarySkill ? Number(primarySkill.hourlyRate) : (profile.hourlyRate || 0),
      skills: profile.professionalSkills?.map(s => s.name) || [],
      availability_tags: [status === 'available' ? 'Available Now' : 'Currently Busy'],
      primary_type: 'manual',
      is_active: true, // Professionals are considered active if they have a profile for now
      status: status,
    };
  }

  /** Redis key for the shared (requester-independent) worker directory. */
  private static readonly LIST_CACHE_KEY = 'workers:list';

  /** Drop the cached directory — call after any profile/skill/rate write. */
  async invalidateWorkerListCache(): Promise<void> {
    await this.redisService.del(WorkersService.LIST_CACHE_KEY).catch(() => {});
  }

  async getAll(requesterId?: string): Promise<WorkerDto[]> {
    // AUDIT FIX (uncached feed + N+1): the full directory is built once and
    // cached for 60s. The requester-specific bit (hide yourself) is applied
    // AFTER the cache read, so one cache entry serves every user.
    const cached = await this.redisService.get(WorkersService.LIST_CACHE_KEY);
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
      Promise.all(eligible.map((p) => this.getWorkerStatus(p.user?.id || p.id))),
      Promise.all(
        eligibleTalent.map((p) => this.getWorkerStatus(p.user?.id || p.id)),
      ),
    ]);

    const allWorkerDtos: WorkerDto[] = [
      ...eligible.map((p, i) => this.mapToDto(p, statuses[i])),
      ...eligibleTalent.map((p, i) => this.mapTalentToDto(p, talentStatuses[i])),
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
      .set(WorkersService.LIST_CACHE_KEY, JSON.stringify(all), 60)
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
      const status = await this.getWorkerStatus(userProfile.user?.id || userProfile.id);
      return this.mapToDto(userProfile, status);
    }

    const status = await this.getWorkerStatus(profile.user?.id || profile.id);
    return this.mapToDto(profile, status);
  }

  // ─────────────────────────────────────────────
  // GO-LIVE TOGGLE (RATE LIMITED TO 2/DAY)
  // ─────────────────────────────────────────────

  private async ensureWorkerProfile(userId: string): Promise<WorkerProfile> {
    let profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });

    const talent = await this.talentRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user', 'professionalSkills'],
    });

    if (!profile && !talent) {
      throw new NotFoundException('Worker profile not found');
    }

    if (talent) {
      const talentSkills = talent.professionalSkills?.map(s => s.name) || [];
      const primaryRate = talent.professionalSkills?.[0]?.hourlyRate ?? talent.hourlyRate ?? 50;
      const primaryTitle = talent.professionalSkills?.[0]?.name ? `${talent.professionalSkills[0].name} Expert` : 'Professional Services';

      if (!profile) {
        profile = this.workersRepository.create({
          user: { id: userId } as any, // fallback if talent.user is undefined
          skills: talentSkills,
          activeSkills: talentSkills,
          hourlyRate: primaryRate,
          bio: talent.experience || '',
          title: primaryTitle,
          isActive: false,
          isFirstJobDone: false,
          verificationStatus: 'PENDING' as any,
        });
        if (talent.user) profile.user = talent.user;
      } else {
        const existingSkills = new Set(profile.skills || []);
        let changed = false;
        for (const s of talentSkills) {
          if (!existingSkills.has(s)) {
            existingSkills.add(s);
            changed = true;
          }
        }
        if (changed) {
          profile.skills = Array.from(existingSkills);
          const active = new Set(profile.activeSkills || []);
          for (const s of profile.skills) active.add(s);
          profile.activeSkills = Array.from(active);
        }
      }
      profile = await this.workersRepository.save(profile);
      profile = await this.healTradeSkills(profile);
    }
    
    return profile!;
  }

  async toggleGoLive(
    id: string,
    coords?: { lat?: number; lng?: number },
  ): Promise<{ isActive: boolean; message: string }> {
    // We assume the ID passed is the internal profile ID or the user ID
    // Check if it's an internal profile ID first, if so get user ID
    let userId = id;
    const directProfile = await this.workersRepository.findOne({ where: { id }, relations: ['user'] });
    if (directProfile && directProfile.user) {
      userId = directProfile.user.id;
    }
    
    const profile = await this.ensureWorkerProfile(userId);

    const todayDateStr = new Date().toISOString().split('T')[0]; // YYYY-MM-DD

    // Reset rate limits if it's a new day
    if (profile.goLiveToggleDate !== todayDateStr) {
      profile.goLiveToggleDate = todayDateStr;
      profile.goLiveToggleCountToday = 0;
    }

    // `isActive` is the state BEFORE this call, so this is the direction of
    // travel. Everything below only restricts GOING LIVE — going offline is
    // always allowed and always free (see the counter note below).
    const goingLive = !profile.isActive;

    if (goingLive) {
      // Wallet floor — admin-tunable (Master Entries → go_live_min_wallet).
      const minWallet = await this.masterEntriesService.getConfigNumber(
        'go_live_min_wallet',
        12,
      );
      if (profile.isFirstJobDone && minWallet > 0) {
        const balance = await this.walletsService.getBalance(profile.user?.id || id);
        if (balance < minWallet) {
          throw new BadRequestException(
            `Minimum Rs.${minWallet} wallet balance required to go live. Please top up.`,
          );
        }
      }

      // Daily go-live cap — admin-tunable (Master Entries →
      // go_live_daily_limit; 0 or blank = unlimited).
      //
      // BUGFIX: this used to count EVERY toggle, so "go live" + "go offline
      // for lunch" hit the old cap of 2 and locked the worker out for the
      // rest of the day. Only going live is counted now.
      const dailyLimit = await this.masterEntriesService.getConfigNumber(
        'go_live_daily_limit',
        6,
      );
      if (dailyLimit > 0 && profile.goLiveToggleCountToday >= dailyLimit) {
        throw new BadRequestException(
          `You have gone live ${dailyLimit} times today, which is the daily limit. Try again tomorrow.`,
        );
      }
    }

    // Process toggle
    profile.isActive = !profile.isActive;
    if (goingLive) profile.goLiveToggleCountToday += 1;

    // Persist GPS from the client when going live so Instant Help can match
    // this worker even when lastLat/lastLng were never written before.
    const lat = coords?.lat;
    const lng = coords?.lng;
    if (
      goingLive &&
      typeof lat === 'number' &&
      typeof lng === 'number' &&
      Number.isFinite(lat) &&
      Number.isFinite(lng)
    ) {
      profile.lastLat = lat;
      profile.lastLng = lng;
    }

    await this.workersRepository.save(profile);
    await this.invalidateWorkerListCache(); // directory shows is_active

    // SYNC WITH REDIS STATUS
    if (!profile.isActive) {
      // Remove from geo index and clear status if going offline
      await this.redisService.del(`worker:location:${userId}`);
      await this.redisService.del(`worker:status:${userId}`);
      await this.redisService.del(`worker:snapshot:${userId}`);
      await this.redisService.unindexWorkerSkills(userId, profile.skills || []);
      // Remove ONLY this worker from the GEO set (ZREM) — a DEL here would
      // wipe every live worker off the map.
      await this.redisService.removeWorkerFromGeoIndex(userId);
    } else {
      // Mark as available if going online
      await this.setWorkerStatus(userId, 'available');
      
      // PERSISTENCE SYNC: warm Redis with coords from this request or DB
      if (profile.lastLat && profile.lastLng) {
        await this.redisService.updateWorkerLocation(
          userId, 
          Number(profile.lastLat), 
          Number(profile.lastLng)
        );
      }

      // CACHE SNAPSHOT: Push full DTO to Redis for search
      const dto = this.mapToDto(profile, 'available');
      await this.redisService.cacheWorkerSnapshot(userId, dto);
      // Only index skills the worker has switched ON (empty/null = all).
      await this.redisService.indexWorkerSkills(userId, this.dispatchableSkills(profile));
    }

    return {
      isActive: profile.isActive,
      message: profile.isActive 
        ? 'You are now LIVE on the map and accepting jobs.' 
        : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
    };
  }

  /** Update the worker's last-known GPS (DB + Redis). Required for Instant
   *  Help matching while live — without Redis location, getNearby skips them. */
  async updateMyLocation(
    userId: string,
    lat: number,
    lng: number,
  ): Promise<{ ok: true }> {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new BadRequestException('lat and lng are required');
    }
    const profile = await this.ensureWorkerProfile(userId);
    profile.lastLat = lat;
    profile.lastLng = lng;
    await this.workersRepository.save(profile);
    if (profile.isActive) {
      await this.redisService.updateWorkerLocation(userId, lat, lng);
    }
    return { ok: true };
  }

  /** Skills that should receive instant dispatch: activeSkills if the worker
   *  curated a subset, otherwise every registered skill (back-compat). */
  private dispatchableSkills(profile: WorkerProfile): string[] {
    const active = (profile.activeSkills || []).filter(
      (s) => (profile.skills || []).includes(s),
    );
    return active.length > 0 ? active : profile.skills || [];
  }

  /**
   * Go Live toggles + Instant Help matching are trade-level only
   * ("Electrician"), not every sub-skill ("Fan installation"). Collapse a
   * polluted skills list back to PRO_TRADE labels, recovering parent trades
   * from sub-skills when needed.
   */
  private async normalizeTradeSkills(skills: string[]): Promise<string[]> {
    const unique = [...new Set((skills || []).map((s) => s.trim()).filter(Boolean))];
    if (unique.length === 0) return [];

    let trades: Array<{ label: string; value?: string | null }> = [];
    try {
      trades = await this.masterEntriesService.findAll(
        MasterEntryType.PRO_TRADE,
        true,
      );
    } catch {
      return unique;
    }
    if (!trades.length) return unique;

    const tradeLabels = new Set(trades.map((t) => t.label));
    const tradeOnly = unique.filter((s) => tradeLabels.has(s));
    if (tradeOnly.length > 0) return tradeOnly;

    const recovered = new Set<string>();
    for (const trade of trades) {
      const subs = (trade.value || '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
      if (unique.some((s) => subs.includes(s))) {
        recovered.add(trade.label);
      }
    }

    try {
      const subEntries = await this.masterEntriesService.findAll(
        MasterEntryType.PRO_SUB_SKILL,
        true,
      );
      for (const sub of subEntries) {
        if (!unique.includes(sub.label)) continue;
        if (sub.category && tradeLabels.has(sub.category)) {
          recovered.add(sub.category);
        }
      }
    } catch {
      // ignore — trade.value CSV recovery above is enough
    }

    return recovered.size > 0 ? [...recovered] : unique;
  }

  /** Persist trade-only skills when a profile still has sub-skill noise. */
  private async healTradeSkills(profile: WorkerProfile): Promise<WorkerProfile> {
    const normalized = await this.normalizeTradeSkills(profile.skills || []);
    const before = [...(profile.skills || [])].sort().join('|');
    const after = [...normalized].sort().join('|');
    if (before === after) return profile;

    profile.skills = normalized;
    const active = (profile.activeSkills || []).filter((s) =>
      normalized.includes(s),
    );
    // Empty activeSkills means "all trades on" — keep that semantics when
    // every former active entry was a sub-skill we dropped.
    profile.activeSkills =
      active.length > 0
        ? active
        : (profile.activeSkills || []).length === 0
          ? []
          : [...normalized];
    return this.workersRepository.save(profile);
  }

  /** Per-service activation: persist which skills accept instant jobs.
   *  If the worker is currently live, the Redis skill index is re-synced so
   *  dispatch immediately respects the new selection. */
  async setActiveSkills(
    userId: string,
    skills: string[],
  ): Promise<{ skills: string[]; activeSkills: string[] }> {
    const profile = await this.ensureWorkerProfile(userId);

    const allowed = profile.skills || [];
    const cleaned = [...new Set(skills)].filter((s) => allowed.includes(s));
    if (skills.length > 0 && cleaned.length === 0) {
      throw new BadRequestException('None of those services are on your profile');
    }
    profile.activeSkills = cleaned;
    await this.workersRepository.save(profile);

    if (profile.isActive) {
      // Re-sync the dispatch index: drop everything, re-add the active set.
      await this.redisService.unindexWorkerSkills(userId, allowed);
      await this.redisService.indexWorkerSkills(userId, this.dispatchableSkills(profile));
    }
    return { skills: allowed, activeSkills: profile.activeSkills || [] };
  }

  /** Go-Live dashboard: skills + activation state + earnings summary. */
  async getDashboard(userId: string): Promise<{
    skills: string[];
    activeSkills: string[];
    isActive: boolean;
    serviceRadiusKm: number;
    earnings: {
      total: number;
      today: number;
      thisWeek: number;
      jobsCompleted: number;
      recent: Array<{
        id: string;
        skill: string;
        amount: number;
        customerName: string;
        completedAt: string | null;
      }>;
    };
  }> {
    const profile = await this.ensureWorkerProfile(userId);
    const healed = await this.healTradeSkills(profile);

    const completed = await this.bookingsRepository.find({
      where: { operator: { id: userId }, status: BookingStatus.COMPLETED },
      relations: ['customer'],
      order: { updatedAt: 'DESC' },
      take: 200,
    });

    const now = new Date();
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfWeek = new Date(startOfDay);
    startOfWeek.setDate(startOfWeek.getDate() - 6); // rolling 7 days

    const amountOf = (b: Booking): number =>
      Number(b.totalAmount ?? b.amount ?? 0) || 0;
    const doneAt = (b: Booking): Date => b.updatedAt;

    let total = 0;
    let today = 0;
    let thisWeek = 0;
    for (const b of completed) {
      const amt = amountOf(b);
      total += amt;
      if (doneAt(b) >= startOfDay) today += amt;
      if (doneAt(b) >= startOfWeek) thisWeek += amt;
    }

    return {
      skills: healed.skills || [],
      activeSkills: healed.activeSkills || [],
      isActive: healed.isActive,
      serviceRadiusKm: healed.serviceRadiusKm ?? DEFAULT_SERVICE_RADIUS_KM,
      earnings: {
        total: Math.round(total * 100) / 100,
        today: Math.round(today * 100) / 100,
        thisWeek: Math.round(thisWeek * 100) / 100,
        jobsCompleted: completed.length,
        recent: completed.slice(0, 10).map((b) => ({
          id: b.id,
          skill: b.skill || 'Service',
          amount: amountOf(b),
          customerName: b.customer?.name || 'Customer',
          completedAt: b.updatedAt ? b.updatedAt.toISOString() : null,
        })),
      },
    };
  }

  async addStrike(userId: string): Promise<void> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) return;
    
    profile.strikeCount = (profile.strikeCount || 0) + 1;
    if (profile.strikeCount >= 3) {
      profile.isActive = false;
      // Note: we can optionally set verificationStatus to SUSPENDED here if available
    }
    await this.workersRepository.save(profile);
  }

  // DEFECT-006: Create (or update) the worker profile. IDEMPOTENT on purpose:
  // the Earn Hourly wizard re-submits on every pass, and the old behaviour
  // (400 'already exists', swallowed by the client) meant a re-run changed
  // nothing AND the user flag below was never set — which is why users were
  // asked to register + verify again on every login.
  async createProfile(userId: string, data: {
    skills: string[];
    hourlyRate: number;
    bio?: string;
    title?: string;
  }): Promise<WorkerProfile> {
    const existing = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });

    const tradeSkills = await this.normalizeTradeSkills(data.skills || []);

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
    await this.invalidateWorkerListCache();

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
    const userIds = profiles.map((p) => p.user?.id).filter(Boolean) as string[];
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
    await this.invalidateWorkerListCache();
    return { userId, verificationStatus: status };
  }

  /// v126 language matching — the pro sets the languages they speak.
  /// Refreshes the cached worker snapshot so broadcast fan-outs see the
  /// change immediately.
  async setLanguages(userId: string, languages: string[]): Promise<{ languages: string[] }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });
    if (!profile) throw new NotFoundException('Worker profile not found');
    profile.languages = languages;
    await this.workersRepository.save(profile);
    await this.invalidateWorkerListCache();
    try {
      const status = await this.getWorkerStatus(userId);
      await this.redisService.cacheWorkerSnapshot(userId, this.mapToDto(profile, status));
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
    await this.invalidateWorkerListCache();
    try {
      const status = await this.getWorkerStatus(userId);
      await this.redisService.cacheWorkerSnapshot(
        userId,
        this.mapToDto(profile, status),
      );
    } catch (e) {
      console.error('[SetServiceRadius] snapshot refresh failed:', e);
    }
    return { serviceRadiusKm: clamped };
  }

  // DEFECT-007: Update hourly rate with 2/day rate limit
  async updateHourlyRate(userId: string, newRate: number): Promise<{ hourlyRate: number }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) throw new NotFoundException('Worker profile not found');

    const todayStr = new Date().toISOString().split('T')[0];
    if (profile.rateUpdateDate !== todayStr) {
      profile.rateUpdateDate = todayStr;
      profile.rateUpdateCountToday = 0;
    }
    if (profile.rateUpdateCountToday >= 2) {
      throw new BadRequestException('Hourly rate can only be updated twice per day.');
    }
    profile.hourlyRate = newRate;
    profile.rateUpdateCountToday += 1;
    await this.workersRepository.save(profile);
    await this.invalidateWorkerListCache();
    return { hourlyRate: newRate };
  }

  // Optimized: Nearby workers filtered by skill using Redis GEO + Skill Index
  async getNearby(requesterId: string, skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
    // 1. Get all workers who have this skill from Redis Skill Index
    let skillWorkerIds = await this.redisService.getWorkerIdsBySkill(skill);
    if (skillWorkerIds.length === 0) return [];

    // 2. GEO pre-filter: one GEOSEARCH narrows the candidate set to the 50km
    //    radius before the per-worker checks below. If the geo query is
    //    unavailable (null), we keep the full skill set — the loop's own
    //    haversine check below remains the source of truth either way.
    const nearbyIds = await this.redisService.searchNearbyWorkerIds(
      lat,
      lng,
      MAX_DISPATCH_RADIUS_KM,
    );
    if (nearbyIds !== null && nearbyIds.length > 0) {
      const nearSet = new Set(nearbyIds);
      const narrowed = skillWorkerIds.filter((id) => nearSet.has(id));
      // Only narrow when the geo index actually knows these workers —
      // an empty intersection with a non-empty skill set may just mean the
      // geo index is cold (e.g. after a Redis restart).
      if (narrowed.length > 0) skillWorkerIds = narrowed;
    }

    // 3. Per-worker distance + snapshot resolution.
    // AUDIT FIX (N+1 on the dispatch hot path): this used to await Redis
    // location → Redis snapshot → (miss) DB profile → status SERIALLY for
    // every candidate — with 15 candidates that's up to 60 sequential
    // round-trips before a single pro is notified. Now every stage is
    // resolved in parallel, and the DB fallback for cache misses is ONE
    // `IN (...)` query instead of one query per worker.
    const candidates = skillWorkerIds.filter((id) => id !== requesterId);

    // 3a. All locations in parallel; keep only those inside the radius.
    const locations = await Promise.all(
      candidates.map((id) => this.redisService.getWorkerLocation(id)),
    );
    const inRadius: { workerId: string; distance: number }[] = [];
    candidates.forEach((workerId, i) => {
      const location = locations[i];
      if (!location) return;
      const distance = this.calculateDistance(lat, lng, location.lat, location.lng);
      // Coarse pre-filter only — the pro's OWN serviceRadiusKm is enforced
      // below, once their snapshot (which carries it) is resolved.
      if (distance <= MAX_DISPATCH_RADIUS_KM) inRadius.push({ workerId, distance });
    });
    if (inRadius.length === 0) return [];

    // Nearest-first candidate cap BEFORE snapshot/status work — keeps Redis
    // and DB load bounded when geo is cold and the skill index is large.
    inRadius.sort((a, b) => a.distance - b.distance);
    const capped = inRadius.slice(0, MAX_NEARBY_CANDIDATES);

    // 3b. All snapshots in parallel.
    const snapshots = await Promise.all(
      capped.map((c) => this.redisService.getWorkerSnapshot(c.workerId)),
    );

    // 3c. Cache misses resolved with a SINGLE DB query + parallel statuses.
    const missIds = capped
      .filter((_, i) => !snapshots[i])
      .map((c) => c.workerId);
    const rebuilt = new Map<string, WorkerDto>();
    if (missIds.length > 0) {
      const profiles = await this.workersRepository.find({
        where: { user: { id: In(missIds) } },
        relations: ['user'],
      });
      const statuses = await Promise.all(
        profiles.map((p) => this.getWorkerStatus(p.user?.id || p.id)),
      );
      await Promise.all(
        profiles.map(async (p, i) => {
          const id = p.user?.id || p.id;
          const dto = this.mapToDto(p, statuses[i]);
          rebuilt.set(id, dto);
          await this.redisService
            .cacheWorkerSnapshot(id, dto)
            .catch(() => {});
        }),
      );
    }

    const result: WorkerDto[] = [];
    capped.forEach((c, i) => {
      const dto = snapshots[i] ?? rebuilt.get(c.workerId);
      if (!dto) return;

      // Skip workers already on a job — Instant Help only notifies available.
      if (dto.status === 'busy') return;

      // ── Worker-set travel limit ──
      // Each pro declares how far they'll travel (Go Live → Service area).
      // A job outside that radius is simply not offered to them — this is
      // what stops a plumber in Kochi being pinged for a job 40 km away.
      // Legacy snapshots cached before this field existed fall back to the
      // default rather than being excluded.
      const limit = Math.min(
        dto.service_radius_km ?? DEFAULT_SERVICE_RADIUS_KM,
        MAX_DISPATCH_RADIUS_KM,
      );
      if (c.distance > limit) return;

      // Surface the real haversine distance so clients can show a true ETA.
      dto.distance_km = Math.round(c.distance * 10) / 10;
      result.push(dto);
    });

    // Among the nearest capped set, prefer higher-rated pros.
    return result.sort((a, b) => (b.rating || 0) - (a.rating || 0));
  }

  /** HAversine formula for distance check */
  private calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
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
      const skillWithChart = skills.find(s => s.rateChart && Object.keys(s.rateChart).length > 0);

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
            includes: ['Up to 3 tasks', 'All tools included', 'Report on completion'],
          });
        }
        if (chart['fullDay'] || chart['8hr']) {
          packages.push({
            name: 'Full Day',
            description: `Full day ${skillWithChart.name} engagement`,
            duration: '8 hrs',
            price: chart['fullDay'] || chart['8hr'],
            isPopular: false,
            includes: ['Unlimited tasks', 'Materials advice', 'Priority rebooking'],
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
        includes: ['Up to 3 tasks', 'All tools included', 'Report on completion'],
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
