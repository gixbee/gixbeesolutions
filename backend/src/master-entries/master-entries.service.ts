import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MasterEntry, MasterEntryType } from './master-entry.entity';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class MasterEntriesService {
  private readonly CACHE_KEY_PREFIX = 'master_entries';

  constructor(
    @InjectRepository(MasterEntry)
    private readonly masterEntryRepo: Repository<MasterEntry>,
    private readonly redisService: RedisService,
  ) {}

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

  async findAll(type?: MasterEntryType, isActive?: boolean): Promise<MasterEntry[]> {
    const cacheKey = `${this.CACHE_KEY_PREFIX}:${type ?? 'all'}:${isActive ?? 'any'}`;
    
    // 1. Try to get from Redis
    const cached = await this.redisService.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }

    // 2. Fetch from Postgres
    const where: any = {};
    if (type) where.type = type;
    if (isActive !== undefined) where.isActive = isActive;
    
    const entries = await this.masterEntryRepo.find({ where, order: { createdAt: 'DESC' } });

    // 3. Store in Redis for 1 hour (master data doesn't change often)
    await this.redisService.set(cacheKey, JSON.stringify(entries), 3600);

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
