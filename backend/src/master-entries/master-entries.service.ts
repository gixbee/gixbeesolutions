import { Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import { MasterEntry, MasterEntryType } from './master-entry.entity';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class MasterEntriesService implements OnModuleInit {
  private readonly CACHE_KEY_PREFIX = 'master_entries';

  constructor(
    @InjectRepository(MasterEntry)
    private readonly masterEntryRepo: Repository<MasterEntry>,
    private readonly redisService: RedisService,
  ) {}

  async onModuleInit() {
    // Seed default PRO_TRADES if none exist
    const count = await this.masterEntryRepo.count({ where: { type: MasterEntryType.PRO_TRADE } });
    if (count === 0) {
      const defaultTrades = [
        { label: 'Electrician', icon: 'bolt_rounded', value: 'Wiring & rewiring,Switch & socket repair,Fan installation,Light fitting,MCB / fuse box,Inverter & battery' },
        { label: 'Plumber', icon: 'plumbing_rounded', value: 'Pipe leaking / dripping,Burst pipe emergency,Wall / ceiling leakage,Joint / fitting leak,Drain & blockage,Toilet repair,Tap & faucet,Water supply' },
        { label: 'Driver', icon: 'directions_car_rounded', value: 'Personal driver (hourly),Outstation trips,Two-wheeler delivery,Goods transport,Airport pickup / drop' },
        { label: 'Cleaner', icon: 'cleaning_services_rounded', value: 'Home deep cleaning,Bathroom cleaning,Kitchen cleaning,Sofa & carpet,Office cleaning,Move-in / move-out' },
        { label: 'Nurse', icon: 'medical_services_rounded', value: 'Elderly care,Patient bedside care,Injection & dressing,Post-surgery care,Baby care' },
        { label: 'Carpenter', icon: 'handyman_rounded', value: 'Furniture repair,Door & window fitting,Modular kitchen,Bed & wardrobe,Custom woodwork' },
        { label: 'AC Technician', icon: 'ac_unit_rounded', value: 'AC servicing,Gas refill,Installation / uninstall,Cooling repair,Water leakage fix' },
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

    await this.seedDefaultConfigs();
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
      value: '6',
      note: 'How many times a worker may go LIVE per day (going offline is free). 0 = unlimited.',
    },
    {
      key: 'go_live_min_wallet',
      value: '12',
      note: 'Minimum wallet balance (Rs.) required to go live, once the first job is done.',
    },
  ];

  private async seedDefaultConfigs(): Promise<void> {
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
    //    behaviour is unchanged (all rows regardless of scope), so the admin
    //    portal keeps seeing everything.
    const base: any = {};
    if (type) base.type = type;
    if (isActive !== undefined) base.isActive = isActive;
    if (category) base.category = category;

    const where = cityId ? [{ ...base, cityId: IsNull() }, { ...base, cityId }] : base;

    const entries = await this.masterEntryRepo.find({ where, order: { createdAt: 'DESC' } });

    // 3. Store in Redis for ~1 hour with ±10% JITTER — with two backend
    //    replicas, identical TTLs expire in lockstep and both replicas miss
    //    simultaneously, stampeding Postgres for this hottest of keys.
    const ttl = 3600 + Math.floor(Math.random() * 721) - 360;
    await this.redisService.set(cacheKey, JSON.stringify(entries), ttl);

    return entries;
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
