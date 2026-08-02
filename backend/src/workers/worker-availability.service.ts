import {
  Injectable,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { WorkerProfile } from './worker-profile.entity';
import { TalentProfile } from '../talent/talent-profile.entity';
import { Booking, BookingStatus } from '../bookings/booking.entity';
import { RedisService } from '../redis/redis.service';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { MasterEntryType } from '../master-entries/master-entry.entity';
import {
  WorkerDto,
  MAX_DISPATCH_RADIUS_KM,
  DEFAULT_SERVICE_RADIUS_KM,
  MAX_NEARBY_CANDIDATES,
} from './worker.shared';

@Injectable()
export class WorkerAvailabilityService {
  /** In-flight job statuses that make a pro ineligible for new Instant Help. */
  private static readonly BUSY_BOOKING_STATUSES = [
    BookingStatus.ACCEPTED,
    BookingStatus.ARRIVED,
    BookingStatus.ACTIVE,
    BookingStatus.CONFIRMED,
  ] as const;


  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    private readonly redisService: RedisService,
    private readonly masterEntriesService: MasterEntriesService,
  ) {}

  async getWorkerStatus(userId: string): Promise<'available' | 'busy'> {
    // 1. Try Redis cache first
    const cachedStatus = await this.redisService.get(`worker:status:${userId}`);
    if (cachedStatus === 'busy') return 'busy';
    if (cachedStatus === 'available') return 'available';

    // 2. Fallback to DB — any accepted-through-active job means busy.
    const activeBooking = await this.bookingsRepository.findOne({
      where: WorkerAvailabilityService.BUSY_BOOKING_STATUSES.map((status) => ({
        operator: { id: userId },
        status,
      })),
    });

    const status = activeBooking ? 'busy' : 'available';
    // 3. Update cache for next time
    await this.redisService.set(`worker:status:${userId}`, status, 3600); // 1hr TTL
    return status;
  }


  async setWorkerStatus(
    userId: string,
    status: 'available' | 'busy',
  ): Promise<void> {
    await this.redisService.set(`worker:status:${userId}`, status, 3600);
    try {
      const snap = await this.redisService.getWorkerSnapshot(userId);
      if (snap && snap.status !== status) {
        await this.redisService.cacheWorkerSnapshot(userId, {
          ...snap,
          status,
        });
      }
    } catch {
      // Snapshot patch is best-effort; live status key remains source of truth.
    }
  }


  /** Public mapper — also used by WorkersService.getAll / getById / snapshot. */
  mapToDto(
    profile: WorkerProfile,
    status: 'available' | 'busy' = 'available',
  ): WorkerDto {
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


  mapTalentToDto(
    profile: TalentProfile,
    status: 'available' | 'busy' = 'available',
  ): WorkerDto {
    const primarySkill = profile.professionalSkills?.[0];
    return {
      id: profile.user?.id || profile.id,
      name: profile.user?.name || 'Unknown Professional',
      title: primarySkill
        ? `${primarySkill.name} Expert`
        : 'Professional Services',
      bio: profile.experience || '',
      image_url: profile.user?.profileImageUrl || 'https://i.pravatar.cc/150',
      rating: 5.0, // Default for new pros
      completed_jobs: 0,
      review_count: 0,
      is_featured: false,
      hourly_rate: primarySkill
        ? Number(primarySkill.hourlyRate)
        : profile.hourlyRate || 0,
      skills: profile.professionalSkills?.map((s) => s.name) || [],
      availability_tags: [
        status === 'available' ? 'Available Now' : 'Currently Busy',
      ],
      primary_type: 'manual',
      is_active: true, // Professionals are considered active if they have a profile for now
      status: status,
    };
  }


  async getNearbyCounts(
    lat: number,
    lng: number,
  ): Promise<Record<string, number>> {
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      throw new BadRequestException('lat and lng are required');
    }
    const cacheKey = `nearby:counts:${lat.toFixed(2)}:${lng.toFixed(2)}`;
    const cached = await this.redisService.get(cacheKey).catch(() => null);
    if (cached) {
      try {
        return JSON.parse(cached) as Record<string, number>;
      } catch {
        // corrupt cache entry — fall through and rebuild
      }
    }

    // Trades from the same admin master the app grid renders (PRO_TRADE).
    let trades: Array<{ label: string }> = [];
    try {
      trades = await this.masterEntriesService.findAll(
        MasterEntryType.PRO_TRADE,
        true,
      );
    } catch {
      trades = [];
    }
    const labels = trades.map((t) => t.label).filter(Boolean);
    if (labels.length === 0) return {};

    // Single GEOSEARCH; null = geo index unavailable (e.g. cold after a
    // Redis restart) — counts then fall back to "live with this skill
    // anywhere", still an upper bound.
    const nearbyIds = await this.redisService.searchNearbyWorkerIds(
      lat,
      lng,
      MAX_DISPATCH_RADIUS_KM,
    );
    const nearSet = nearbyIds === null ? null : new Set(nearbyIds);

    const counts: Record<string, number> = {};
    await Promise.all(
      labels.map(async (label) => {
        try {
          const ids = await this.redisService.getWorkerIdsBySkill(label);
          counts[label] =
            nearSet === null
              ? ids.length
              : ids.filter((id) => nearSet.has(id)).length;
        } catch {
          counts[label] = 0;
        }
      }),
    );

    await this.redisService
      .set(cacheKey, JSON.stringify(counts), 45)
      .catch(() => {});
    return counts;
  }


  async getNearby(
    requesterId: string,
    skill: string,
    lat: number,
    lng: number,
    radiusStretch = 1,
  ): Promise<WorkerDto[]> {
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
    const rejectedIds = await this.redisService.getRejectedWorkersForJob(
      requesterId,
      skill,
    );
    const rejectedSet = new Set(rejectedIds);
    const candidates = skillWorkerIds.filter(
      (id) => id !== requesterId && !rejectedSet.has(id),
    );

    // 3a. All locations in parallel; keep only those inside the radius.
    const locations = await Promise.all(
      candidates.map((id) => this.redisService.getWorkerLocation(id)),
    );
    const inRadius: { workerId: string; distance: number }[] = [];
    candidates.forEach((workerId, i) => {
      const location = locations[i];
      if (!location) return;
      const distance = this.calculateDistance(
        lat,
        lng,
        location.lat,
        location.lng,
      );
      // Coarse pre-filter only — the pro's OWN serviceRadiusKm is enforced
      // below, once their snapshot (which carries it) is resolved.
      if (distance <= MAX_DISPATCH_RADIUS_KM)
        inRadius.push({ workerId, distance });
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
          await this.redisService.cacheWorkerSnapshot(id, dto).catch(() => {});
        }),
      );
    }

    // Live busy check — do NOT trust snapshot.status alone. Snapshots can
    // stay "available" for hours after accept, which was pinging Worker A
    // with new Instant Help offers while they were already on a job.
    const liveStatuses = await Promise.all(
      capped.map((c) => this.getWorkerStatus(c.workerId)),
    );

    const result: WorkerDto[] = [];
    capped.forEach((c, i) => {
      const dto = snapshots[i] ?? rebuilt.get(c.workerId);
      if (!dto) return;

      const liveStatus = liveStatuses[i];
      if (liveStatus === 'busy') return;
      dto.status = liveStatus;

      // ── Worker-set travel limit ──
      // Each pro declares how far they'll travel (Go Live → Service area).
      // A job outside that radius is simply not offered to them — this is
      // what stops a plumber in Kochi being pinged for a job 40 km away.
      // Legacy snapshots cached before this field existed fall back to the
      // default rather than being excluded.
      const limit = Math.min(
        (dto.service_radius_km ?? DEFAULT_SERVICE_RADIUS_KM) *
          Math.max(1, radiusStretch),
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


  calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
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

}
