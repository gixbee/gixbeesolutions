import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkerProfile, VerificationStatus } from './worker-profile.entity';
import { TalentProfile } from '../talent/talent-profile.entity';
import { User } from '../users/user.entity';
import { Booking, BookingStatus } from '../bookings/booking.entity';
import { WalletsService } from '../wallets/wallets.service';
import { RedisService } from '../redis/redis.service';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { MasterEntryType } from '../master-entries/master-entry.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { JobCredit } from '../billing/job-credit.entity';
import {
  SUSPENSION_STRIKE_THRESHOLD,
  WALLET_PAYMENTS_ENABLED,
  WORKERS_LIST_CACHE_KEY,
  DEFAULT_SERVICE_RADIUS_KM,
} from './worker.shared';
import { WorkerAvailabilityService } from './worker-availability.service';

@Injectable()
export class WorkerGoLiveService {
  private readonly logger = new Logger(WorkerGoLiveService.name);
  private static readonly IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(TalentProfile)
    private readonly talentRepository: Repository<TalentProfile>,
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
    @InjectRepository(JobCredit)
    private readonly jobCreditRepository: Repository<JobCredit>,
    private readonly walletsService: WalletsService,
    private readonly redisService: RedisService,
    private readonly masterEntriesService: MasterEntriesService,
    private readonly notificationsService: NotificationsService,
    private readonly workerAvailabilityService: WorkerAvailabilityService,
  ) {}

  istToday(): string {
    return new Date().toLocaleDateString('en-CA', {
      timeZone: 'Asia/Kolkata',
    });
  }


  istStartOfDay(): Date {
    const nowIst = new Date(Date.now() + WorkerGoLiveService.IST_OFFSET_MS);
    return new Date(
      Date.UTC(
        nowIst.getUTCFullYear(),
        nowIst.getUTCMonth(),
        nowIst.getUTCDate(),
      ) - WorkerGoLiveService.IST_OFFSET_MS,
    );
  }


  async ensureWorkerProfile(userId: string): Promise<WorkerProfile> {
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
      const talentSkills = talent.professionalSkills?.map((s) => s.name) || [];
      const primaryRate =
        talent.professionalSkills?.[0]?.hourlyRate ?? talent.hourlyRate ?? 50;
      const primaryTitle = talent.professionalSkills?.[0]?.name
        ? `${talent.professionalSkills[0].name} Expert`
        : 'Professional Services';

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

    // FLAG HEAL (client bug: "Go Live asks me to Register as Pro even though
    // my data is in Earn Hourly"): talent-path registration creates the
    // WorkerProfile lazily HERE, but only createProfile() ever flipped
    // users.hasWorkerProfile — so GET /auth/profile kept reporting false and
    // the app routed verified pros back to the wizard forever. Heal the flag
    // whenever the loaded relation shows it stale (idempotent, no extra
    // UPDATE once healed).
    const owner = profile!.user;
    if (owner?.id && owner.hasWorkerProfile !== true) {
      await this.usersRepository
        .update(owner.id, { hasWorkerProfile: true })
        .catch(() => {});
      owner.hasWorkerProfile = true;
    }

    return profile!;
  }


  async toggleGoLive(
    id: string,
    coords?: { lat?: number; lng?: number; active?: boolean },
  ): Promise<{ isActive: boolean; message: string }> {
    // We assume the ID passed is the internal profile ID or the user ID
    // Check if it's an internal profile ID first, if so get user ID
    let userId = id;
    const directProfile = await this.workersRepository.findOne({
      where: { id },
      relations: ['user'],
    });
    if (directProfile && directProfile.user) {
      userId = directProfile.user.id;
    }

    const profile = await this.ensureWorkerProfile(userId);

    // IST calendar date — NOT toISOString() (UTC), which doesn't roll over
    // until 05:30 IST and kept workers locked out past Indian midnight.
    const todayDateStr = this.istToday();

    // Reset rate limits if it's a new day
    if (profile.goLiveToggleDate !== todayDateStr) {
      profile.goLiveToggleDate = todayDateStr;
      profile.goLiveToggleCountToday = 0;
    }

    // Desired-state (`active`) is preferred — a lost response + retry must
    // not flip the pro offline. Omit `active` to keep legacy flip behaviour.
    const targetActive =
      typeof coords?.active === 'boolean' ? coords.active : !profile.isActive;

    // Already in the desired state — no-op success (idempotent).
    if (profile.isActive === targetActive) {
      return {
        isActive: profile.isActive,
        message: profile.isActive
          ? 'You are now LIVE on the map and accepting jobs.'
          : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
      };
    }

    // Direction of travel. Gates below only restrict GOING LIVE — going
    // offline is always allowed and always free.
    const goingLive = targetActive;

    if (goingLive) {
      if (profile.verificationStatus !== VerificationStatus.VERIFIED) {
        throw new BadRequestException(
          'Your profile is not verified yet. Please complete the verification process to go live.',
        );
      }

      // ── Strike suspension gate ──
      // 3+ counting strikes (ACTIVE / APPEALED / UPHELD) = suspended from
      // going live until an appeal is overturned or an admin clears it.
      // Enforced HERE (not just isActive=false) because a worker could
      // otherwise simply toggle back on after a forfeit deactivated them.
      if ((profile.strikeCount || 0) >= SUSPENSION_STRIKE_THRESHOLD) {
        throw new BadRequestException(
          'Your account is suspended after repeated job violations. ' +
            'Open Profile → Strikes to see the reasons and file an appeal — ' +
            'our team reviews every appeal.',
        );
      }

      // Check Job Credits balance
      const creditRow = await this.jobCreditRepository.findOne({
        where: { user: { id: userId } },
      });
      const credits = creditRow ? creditRow.balance : 0;
      if (credits <= 0) {
        throw new BadRequestException(
          'You need job credits to go live and accept new bookings. Please buy a job pack to continue.',
        );
      }

      // Daily go-live cap — admin-tunable (Master Entries →
      // go_live_daily_limit; 0 or blank = unlimited).
      //
      // PRODUCT DECISION (periodic fee model, Jul 2026): with the wallet
      // system off and workers paying per COMPLETED job (not per go-live
      // session), there is no longer any cost to going live. The cap was
      // designed to prevent free-riding when each session consumed wallet
      // balance; it is now irrelevant. Default changed to 0 (unlimited).
      // An admin can still set a positive value in Master Entries if abuse
      // becomes a problem later.
      const dailyLimit = await this.masterEntriesService.getConfigNumber(
        'go_live_daily_limit',
        0, // 0 = unlimited (was 6 under the old wallet model)
      );
      if (dailyLimit > 0 && profile.goLiveToggleCountToday >= dailyLimit) {
        throw new BadRequestException(
          `You have gone live ${dailyLimit} times today, which is the daily limit. Try again tomorrow.`,
        );
      }

      // ── Location gate ──
      // A live worker with NO coordinates never enters the Redis geo index —
      // they'd burn a go-live session appearing online while receiving zero
      // jobs. The app enforces this client-side (GPS-required sheet); this
      // closes the loop for modified/legacy clients: going live requires
      // coords in THIS request, or a previously persisted location we can
      // warm the index with (the 30s heartbeat then keeps it fresh).
      const reqLat = coords?.lat;
      const reqLng = coords?.lng;
      const hasRequestCoords =
        typeof reqLat === 'number' &&
        typeof reqLng === 'number' &&
        Number.isFinite(reqLat) &&
        Number.isFinite(reqLng);
      const hasStoredCoords =
        profile.lastLat != null && profile.lastLng != null;
      if (!hasRequestCoords && !hasStoredCoords) {
        throw new BadRequestException(
          'Location is required to go live — customers are matched to pros ' +
            'by live GPS. Enable location and try again.',
        );
      }
    }

    // Apply desired / flipped state
    profile.isActive = targetActive;
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
    await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {}); // directory shows is_active

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
      await this.workerAvailabilityService.setWorkerStatus(userId, 'available');

      // PERSISTENCE SYNC: warm Redis with coords from this request or DB
      if (profile.lastLat && profile.lastLng) {
        await this.redisService.updateWorkerLocation(
          userId,
          Number(profile.lastLat),
          Number(profile.lastLng),
        );
      }

      // CACHE SNAPSHOT: Push full DTO to Redis for search
      const dto = this.workerAvailabilityService.mapToDto(profile, 'available');
      await this.redisService.cacheWorkerSnapshot(userId, dto);
      // Only index skills the worker has switched ON (empty/null = all).
      await this.redisService.indexWorkerSkills(
        userId,
        this.dispatchableSkills(profile),
      );
    }

    return {
      isActive: profile.isActive,
      message: profile.isActive
        ? 'You are now LIVE on the map and accepting jobs.'
        : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
    };
  }

  // ── Periodic fee model ("N jobs, then pay") ─────────────────────────

  /** Jobs included per paid period (Master Entries → go_live_jobs_per_payment).
   *  0 = model OFF → the legacy per-booking ₹12 wallet drip applies. */
  async periodicJobsPerPayment(): Promise<number> {
    return this.masterEntriesService.getConfigNumber(
      'go_live_jobs_per_payment',
      0,
    );
  }

  /** Count a COMPLETED job against the worker's current period. Atomic SQL
   *  increment; NO-OP while the model is off, so enabling it later starts
   *  every worker at 0 (first period free). */
  async recordCompletedJobForPeriod(userId: string): Promise<void> {
    const jobsIncluded = await this.periodicJobsPerPayment();
    if (jobsIncluded <= 0) return;
    const res = await this.workersRepository
      .createQueryBuilder()
      .update(WorkerProfile)
      .set({ jobsSincePayment: () => '"jobsSincePayment" + 1' })
      .where('"userId" = :uid', { uid: userId })
      .execute();
    this.logger.log(
      `[PeriodFee] +1 completed job for ${userId} (rows: ${res.affected ?? 0}, plan: ${jobsIncluded}/period)`,
    );

    // If they hit the limit, force them offline immediately so they can't receive more jobs.
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (
      profile &&
      profile.isActive &&
      profile.jobsSincePayment >= jobsIncluded
    ) {
      await this.forceOffline(userId);
      this.logger.log(
        `[PeriodFee] Worker ${userId} hit limit (${profile.jobsSincePayment}/${jobsIncluded}), forced offline.`,
      );
    }
  }

  async forceOffline(userId: string): Promise<void> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (profile && profile.isActive) {
      profile.isActive = false;
      await this.workersRepository.save(profile);

      await this.redisService.del(`worker:location:${userId}`);
      await this.redisService.del(`worker:status:${userId}`);
      await this.redisService.del(`worker:snapshot:${userId}`);
      await this.redisService.unindexWorkerSkills(userId, profile.skills || []);
      await this.redisService.removeWorkerFromGeoIndex(userId);

      await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});

      this.logger.log(`Worker ${userId} forced offline.`);
    }
  }

  /** Fulfilment for a Razorpay PERIOD_FEE payment — called by the payments
   *  webhook after signature verification. Direct payment, NO wallet
   *  involvement: unlock the next batch and tell the pro. */
  async markPeriodFeePaid(userId: string): Promise<void> {
    await this.workersRepository
      .createQueryBuilder()
      .update(WorkerProfile)
      .set({ jobsSincePayment: 0 })
      .where('"userId" = :uid', { uid: userId })
      .execute();
    const jobsIncluded = await this.periodicJobsPerPayment();
    this.notificationsService
      .sendToUser(userId, {
        title: 'Payment received',
        body: `Your next ${jobsIncluded} jobs are unlocked — go live when ready!`,
        data: { type: 'period_fee_paid' },
      })
      .catch(() => {});
  }

  /** Legacy wallet period-fee path — dormant while wallet OFF (ARCH-004).
   *  Live checkout: POST /payments/period-fee/order + Razorpay webhook. */
  async payPeriodFee(userId: string): Promise<{
    message: string;
    jobsIncluded: number;
    jobsUsed: number;
    paymentDue: boolean;
  }> {
    if (!WALLET_PAYMENTS_ENABLED) {
      throw new BadRequestException(
        'Period fee is paid via Razorpay — use POST /payments/period-fee/order',
      );
    }
    const jobsIncluded = await this.periodicJobsPerPayment();
    if (jobsIncluded <= 0) {
      throw new BadRequestException(
        'The per-jobs payment plan is not enabled.',
      );
    }
    const profile = await this.ensureWorkerProfile(userId);
    const jobsUsed = profile.jobsSincePayment ?? 0;
    if (jobsUsed < jobsIncluded) {
      return {
        message: `No payment due yet — ${jobsIncluded - jobsUsed} of your ${jobsIncluded} included jobs remain.`,
        jobsIncluded,
        jobsUsed,
        paymentDue: false,
      };
    }
    const fee = await this.masterEntriesService.getConfigNumber(
      'go_live_period_fee',
      49,
    );
    if (fee > 0) {
      await this.walletsService.charge(
        userId,
        fee,
        `Gixbee platform fee — next ${jobsIncluded} jobs`,
      );
    }
    profile.jobsSincePayment = 0;
    await this.workersRepository.save(profile);
    return {
      message: `Payment received — your next ${jobsIncluded} jobs are unlocked. Go live!`,
      jobsIncluded,
      jobsUsed: 0,
      paymentDue: false,
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
  dispatchableSkills(profile: WorkerProfile): string[] {
    const active = (profile.activeSkills || []).filter((s) =>
      (profile.skills || []).includes(s),
    );
    return active.length > 0 ? active : profile.skills || [];
  }

  /**
   * Go Live toggles + Instant Help matching are trade-level only
   * ("Electrician"), not every sub-skill ("Fan installation"). Collapse a
   * polluted skills list back to PRO_TRADE labels, recovering parent trades
   * from sub-skills when needed.
   */
  async normalizeTradeSkills(skills: string[]): Promise<string[]> {
    const unique = [
      ...new Set((skills || []).map((s) => s.trim()).filter(Boolean)),
    ];
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
  async healTradeSkills(
    profile: WorkerProfile,
  ): Promise<WorkerProfile> {
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
      throw new BadRequestException(
        'None of those services are on your profile',
      );
    }
    profile.activeSkills = cleaned;
    await this.workersRepository.save(profile);

    if (profile.isActive) {
      // Re-sync the dispatch index: drop everything, re-add the active set.
      await this.redisService.unindexWorkerSkills(userId, allowed);
      await this.redisService.indexWorkerSkills(
        userId,
        this.dispatchableSkills(profile),
      );
    }
    return { skills: allowed, activeSkills: profile.activeSkills || [] };
  }

  /** Go-Live dashboard: skills + activation state + earnings summary. */
  async getDashboard(userId: string): Promise<{
    skills: string[];
    activeSkills: string[];
    isActive: boolean;
    verificationStatus: string;
    rating: number;
    serviceRadiusKm: number;
    jobCredits: number;
    feeModel: {
      enabled: boolean;
      jobsIncluded: number;
      jobsUsed: number;
      fee: number;
      paymentDue: boolean;
    };
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

    // Job credits balance
    const creditRecord = await this.jobCreditRepository.findOne({
      where: { user: { id: userId } },
    });
    const jobCredits = creditRecord?.balance ?? 0;

    // Periodic fee plan state for the Go Live screen's plan card.
    const feeJobsIncluded = await this.periodicJobsPerPayment();
    const feeAmount =
      feeJobsIncluded > 0
        ? await this.masterEntriesService.getConfigNumber(
            'go_live_period_fee',
            49,
          )
        : 0;
    const feeJobsUsed = healed.jobsSincePayment ?? 0;

    const completed = await this.bookingsRepository.find({
      where: { operator: { id: userId }, status: BookingStatus.COMPLETED },
      relations: ['customer'],
      order: { updatedAt: 'DESC' },
      take: 200,
    });

    const startOfDay = this.istStartOfDay(); // IST midnight, not server-local
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
      verificationStatus: healed.verificationStatus,
      rating: healed.rating || 0,
      serviceRadiusKm: healed.serviceRadiusKm ?? DEFAULT_SERVICE_RADIUS_KM,
      jobCredits,
      feeModel: {
        enabled: feeJobsIncluded > 0,
        jobsIncluded: feeJobsIncluded,
        jobsUsed: feeJobsUsed,
        fee: feeAmount,
        paymentDue: feeJobsIncluded > 0 && feeJobsUsed >= feeJobsIncluded,
      },
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

}
