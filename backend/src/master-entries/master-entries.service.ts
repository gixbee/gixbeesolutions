import {
  Injectable,
  Logger,
  NotFoundException,
  OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import { MasterEntry, MasterEntryType } from './master-entry.entity';
import { RedisService } from '../redis/redis.service';
import { parsePagination } from '../common/pagination';

/** Safety ceiling for the cached catalog read (app + getConfig). */
const MAX_CACHED_ENTRIES = 2000;

@Injectable()
export class MasterEntriesService implements OnModuleInit {
  private readonly logger = new Logger(MasterEntriesService.name);
  private readonly CACHE_KEY_PREFIX = 'master_entries';

  constructor(
    @InjectRepository(MasterEntry)
    private readonly masterEntryRepo: Repository<MasterEntry>,
    private readonly redisService: RedisService,
  ) {}

  async onModuleInit() {
    // Seed default PRO_TRADES if none exist
    const count = await this.masterEntryRepo.count({
      where: { type: MasterEntryType.PRO_TRADE },
    });
    if (count === 0) {
      const defaultTrades = [
        {
          label: 'Electrician',
          icon: 'bolt_rounded',
          value:
            'Wiring & rewiring,Switch & socket repair,Fan installation,Light fitting,MCB / fuse box,Inverter & battery',
        },
        {
          label: 'Plumber',
          icon: 'plumbing_rounded',
          value:
            'Pipe leaking / dripping,Burst pipe emergency,Wall / ceiling leakage,Joint / fitting leak,Drain & blockage,Toilet repair,Tap & faucet,Water supply',
        },
        {
          label: 'Driver',
          icon: 'directions_car_rounded',
          value:
            'Personal driver (hourly),Outstation trips,Two-wheeler delivery,Goods transport,Airport pickup / drop',
        },
        {
          label: 'Cleaner',
          icon: 'cleaning_services_rounded',
          value:
            'Home deep cleaning,Bathroom cleaning,Kitchen cleaning,Sofa & carpet,Office cleaning,Move-in / move-out',
        },
        {
          label: 'Nurse',
          icon: 'medical_services_rounded',
          value:
            'Elderly care,Patient bedside care,Injection & dressing,Post-surgery care,Baby care',
        },
        {
          label: 'Carpenter',
          icon: 'handyman_rounded',
          value:
            'Furniture repair,Door & window fitting,Modular kitchen,Bed & wardrobe,Custom woodwork',
        },
        {
          label: 'AC Technician',
          icon: 'ac_unit_rounded',
          value:
            'AC servicing,Gas refill,Installation / uninstall,Cooling repair,Water leakage fix',
        },
      ];

      for (const trade of defaultTrades) {
        await this.create({
          type: MasterEntryType.PRO_TRADE,
          label: trade.label,
          icon: trade.icon,
          value: '',
          isActive: true,
        });

        const subSkills = trade.value.split(',');
        for (const sub of subSkills) {
          await this.create({
            type: MasterEntryType.PRO_SUB_SKILL,
            label: sub.trim(),
            value: sub.trim(),
            category: trade.label,
            isActive: true,
          });
        }
      }
      console.log('Seeded default PRO_TRADE and PRO_SUB_SKILL entries');
    }

    await this.seedExpandedTrades();
    await this.seedDefaultConfigs();
  }

  // ── Catalog expansion (JOBOY-parity trades, Jul 2026) ────────────────
  //
  // Seeded INACTIVE: every visible trade is a promise that a live pro
  // exists, and an instant request into an empty trade dead-ends at the
  // No Workers screen. Flip a trade on in Admin → Master Entries only
  // once ~3 pros are registered for it in the launch city. Idempotent:
  // checked per-label on every boot, so it's safe across deploys and
  // never duplicates rows or resurrects admin-deleted trades' sub-skills
  // (sub-skills are only created together with their trade).
  private static readonly EXPANDED_TRADES: Array<{
    label: string;
    icon: string;
    subSkills: string[];
  }> = [
    {
      label: 'Painter',
      icon: 'format_paint_rounded',
      subSkills: [
        'Interior painting',
        'Exterior painting',
        'Putty & primer',
        'Wood polish',
        'Waterproof coating',
      ],
    },
    {
      label: 'Appliance Technician',
      icon: 'local_laundry_service_rounded',
      subSkills: [
        'Washing machine',
        'Fridge',
        'TV repair',
        'Microwave oven',
        'Gas stove',
        'Water purifier',
      ],
    },
    {
      label: 'Pest Control',
      icon: 'pest_control_rounded',
      subSkills: [
        'Cockroach control',
        'Termite treatment',
        'Rodent control',
        'Bed bugs',
        'Mosquito treatment',
      ],
    },
    {
      label: 'Beautician',
      icon: 'spa_rounded',
      subSkills: [
        'Haircut & styling',
        'Facial & cleanup',
        'Mehendi',
        'Bridal makeup',
        'Waxing & threading',
      ],
    },
    {
      label: 'Electronics Repair',
      icon: 'devices_rounded',
      subSkills: [
        'Mobile repair',
        'Laptop repair',
        'Desktop repair',
        'CCTV installation',
        'Tablet repair',
      ],
    },
    {
      label: 'Gardener',
      icon: 'grass_rounded',
      subSkills: [
        'Grass cutting',
        'Tree trimming',
        'Garden maintenance',
        'Landscaping',
      ],
    },
    {
      label: 'Renovation Pro',
      icon: 'construction_rounded',
      subSkills: [
        'Tile work',
        'Waterproofing',
        'Aluminium fabrication',
        'False ceiling',
        'Truss & roofing work',
      ],
    },
  ];

  /** Kerala-specific additions to the EXISTING Cleaner trade. */
  private static readonly CLEANER_EXTRA_SUB_SKILLS = [
    'Water tank cleaning',
    'Well cleaning',
  ];

  private async seedExpandedTrades(): Promise<void> {
    for (const trade of MasterEntriesService.EXPANDED_TRADES) {
      const existing = await this.masterEntryRepo.findOne({
        where: { type: MasterEntryType.PRO_TRADE, label: trade.label },
      });
      if (existing) continue;

      await this.create({
        type: MasterEntryType.PRO_TRADE,
        label: trade.label,
        icon: trade.icon,
        value: '',
        isActive: false, // activate in the portal once pros are recruited
      });
      for (const sub of trade.subSkills) {
        await this.create({
          type: MasterEntryType.PRO_SUB_SKILL,
          label: sub,
          value: sub,
          category: trade.label,
          isActive: true,
        });
      }
      console.log(
        `Seeded PRO_TRADE ${trade.label} (INACTIVE) with ${trade.subSkills.length} sub-skills`,
      );
    }

    // Cleaner extras — checked individually against the existing trade.
    for (const sub of MasterEntriesService.CLEANER_EXTRA_SUB_SKILLS) {
      const existing = await this.masterEntryRepo.findOne({
        where: {
          type: MasterEntryType.PRO_SUB_SKILL,
          label: sub,
          category: 'Cleaner',
        },
      });
      if (existing) continue;
      await this.create({
        type: MasterEntryType.PRO_SUB_SKILL,
        label: sub,
        value: sub,
        category: 'Cleaner',
        isActive: true,
      });
      console.log(`Seeded Cleaner sub-skill: ${sub}`);
    }
  }

  // ── Runtime configuration (admin-editable) ─────────────────────────────────
  //
  // CONVENTION for CONFIGURATION entries:
  //    label = the setting KEY   (e.g. 'go_live_daily_limit')
  //    value = the setting VALUE (e.g. '6')
  // Admin → Master Entries → type "Configuration" edits these live; the change
  // takes effect on the next request (the master-entry cache is cleared on
  // every write). Code must ALWAYS pass a sane fallback — a deleted or
  // mistyped row must never brick a flow.

  /** Settings seeded once so the admin has something to edit rather than
   *  having to guess the exact key names. */
  private static readonly DEFAULT_CONFIGS: Array<{
    key: string;
    value: string;
    note: string;
  }> = [
    {
      key: 'go_live_daily_limit',
      value: '0',
      note: 'How many times a worker may go LIVE per day (going offline is free). 0 = unlimited. Changed from 6 to 0 (Jul 2026) — periodic fee model charges per completed job, not per session.',
    },
    {
      key: 'go_live_jobs_per_payment',
      value: '3',
      note: 'Periodic fee plan: completed jobs included per payment. Worker pays the period fee after using them to go live again. 0 = plan OFF.',
    },
    {
      key: 'go_live_period_fee',
      value: '49',
      note: 'Periodic fee plan: Rs. charged (direct Razorpay) to unlock the next batch of included jobs.',
    },
    {
      key: 'instant_petrol_per_km',
      value: '10',
      note: 'Instant Help petrol charge in Rs. per one-way km from the worker accept location to the customer.',
    },
  ];

  private async seedDefaultConfigs(): Promise<void> {
    // ONE-TIME MIGRATION: go_live_daily_limit was seeded as '6' under the
    // old wallet model. Under the periodic fee model (Jul 2026) workers pay
    // per COMPLETED job, not per session, so the cap is irrelevant. Reset
    // any existing '6' entry to '0' (unlimited) so deployed instances get
    // the fix on the next boot without a manual DB change.
    const existingLimit = await this.masterEntryRepo.findOne({
      where: {
        type: MasterEntryType.CONFIGURATION,
        label: 'go_live_daily_limit',
      },
    });
    if (existingLimit && existingLimit.value === '6') {
      existingLimit.value = '0';
      existingLimit.category =
        'How many times a worker may go LIVE per day. 0 = unlimited. ' +
        'Reset from 6 to 0 (Jul 2026) — periodic fee model charges per completed job, not per session.';
      await this.masterEntryRepo.save(existingLimit);
      await this.clearCache();
      console.log(
        'MIGRATION: go_live_daily_limit reset from 6 to 0 (periodic fee model)',
      );
    }

    for (const cfg of MasterEntriesService.DEFAULT_CONFIGS) {
      const existing = await this.masterEntryRepo.findOne({
        where: { type: MasterEntryType.CONFIGURATION, label: cfg.key },
      });
      if (existing) continue;
      await this.create({
        type: MasterEntryType.CONFIGURATION,
        label: cfg.key,
        value: cfg.value,
        category: cfg.note,
        isActive: true,
      });
      console.log(`Seeded CONFIGURATION ${cfg.key}=${cfg.value}`);
    }
  }

  /** Raw string value of an admin-editable setting, or null if absent. */
  async getConfig(key: string): Promise<string | null> {
    const entries = await this.findAll(MasterEntryType.CONFIGURATION, true);
    const hit = entries.find((e) => e.label === key);
    return hit?.value ?? null;
  }

  /** Numeric setting with a mandatory fallback. A missing, disabled, blank or
   *  non-numeric row silently falls back — config must never break dispatch. */
  async getConfigNumber(key: string, fallback: number): Promise<number> {
    const raw = await this.getConfig(key);
    if (raw === null || raw.trim() === '') return fallback;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private async clearCache(): Promise<void> {
    const keys = await this.redisService.keys(`${this.CACHE_KEY_PREFIX}:*`);
    if (keys.length > 0) {
      await this.redisService.del(...keys);
    }
  }

  async create(data: Partial<MasterEntry>): Promise<MasterEntry> {
    const entry = this.masterEntryRepo.create(data);
    const result = await this.masterEntryRepo.save(entry);
    await this.clearCache();
    return result;
  }

  /**
   * Cached catalog for the app / getConfig. Hard-capped so a cache miss can
   * never dump an unbounded table into memory. Prefer {@link adminList} for
   * the portal's paginated browser.
   */
  async findAll(
    type?: MasterEntryType,
    isActive?: boolean,
    category?: string,
    cityId?: string,
  ): Promise<MasterEntry[]> {
    const cacheKey = `${this.CACHE_KEY_PREFIX}:${type ?? 'all'}:${isActive ?? 'any'}:${category ?? 'all'}:${cityId ?? 'all'}`;

    // 1. Try to get from Redis
    const cached = await this.redisService.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }

    // 2. Fetch from Postgres. When cityId is given, return GLOBAL entries
    //    (cityId NULL) plus entries scoped to that city — an OR expressed as
    //    two where-branches sharing the common filters. Without cityId the
    //    behaviour is unchanged (all rows regardless of scope).
    const base: any = {};
    if (type) base.type = type;
    if (isActive !== undefined) base.isActive = isActive;
    if (category) base.category = category;

    const where = cityId
      ? [
          { ...base, cityId: IsNull() },
          { ...base, cityId },
        ]
      : base;

    const entries = await this.masterEntryRepo.find({
      where,
      order: { createdAt: 'DESC' },
      take: MAX_CACHED_ENTRIES,
    });
    if (entries.length >= MAX_CACHED_ENTRIES) {
      this.logger.warn(
        `master_entries findAll hit safety cap ${MAX_CACHED_ENTRIES} for ${cacheKey} — narrow filters or raise the cap`,
      );
    }

    // 3. Store in Redis for ~1 hour with ±10% JITTER — with two backend
    //    replicas, identical TTLs expire in lockstep and both replicas miss
    //    simultaneously, stampeding Postgres for this hottest of keys.
    const ttl = 3600 + Math.floor(Math.random() * 721) - 360;
    await this.redisService.set(cacheKey, JSON.stringify(entries), ttl);

    return entries;
  }

  /** Paginated admin browser — never caches a page of the full table. */
  async adminList(
    type?: MasterEntryType,
    isActive?: boolean,
    page = 1,
    limit = 50,
  ): Promise<MasterEntry[]> {
    const p = parsePagination(page, limit);
    const where: any = {};
    if (type) where.type = type;
    if (isActive !== undefined) where.isActive = isActive;
    return this.masterEntryRepo.find({
      where,
      order: { createdAt: 'DESC' },
      skip: p.skip,
      take: p.limit,
    });
  }

  async findOne(id: string): Promise<MasterEntry> {
    const entry = await this.masterEntryRepo.findOne({ where: { id } });
    if (!entry) throw new NotFoundException('Master entry not found');
    return entry;
  }

  async update(id: string, data: Partial<MasterEntry>): Promise<MasterEntry> {
    const entry = await this.findOne(id);
    Object.assign(entry, data);
    const result = await this.masterEntryRepo.save(entry);
    await this.clearCache();
    return result;
  }

  async remove(id: string): Promise<void> {
    const entry = await this.findOne(id);
    await this.masterEntryRepo.remove(entry);
    await this.clearCache();
  }
}
