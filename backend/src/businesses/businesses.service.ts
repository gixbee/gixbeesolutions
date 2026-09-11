import {
  Injectable,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Business } from './business.entity';
import { User } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
import { stripPrivateFields } from '../common/sanitize';
import { CreateBusinessDto } from './dto/create-business.dto';

@Injectable()
export class BusinessesService {
  // AUDIT FIX: the admin/moderation list hit Postgres on every request.
  // 60s cache per status filter, invalidated on create + status change.
  private static readonly LIST_CACHE_PREFIX = 'businesses:list';

  constructor(
    @InjectRepository(Business)
    private readonly businessRepo: Repository<Business>,
    private readonly redisService: RedisService,
  ) {}

  private async invalidateListCache(): Promise<void> {
    const keys = await this.redisService
      .keys(`${BusinessesService.LIST_CACHE_PREFIX}:*`)
      .catch(() => [] as string[]);
    if (keys.length > 0) {
      await this.redisService.del(...keys).catch(() => {});
    }
  }

  /**
   * Flutter sends free-text `address`; the entity column is `location`
   * (admin portal reads `b.location`). Client-only fields specialty/phone
   * are intentionally dropped — they are not schema columns.
   */
  async create(ownerId: string, data: CreateBusinessDto): Promise<Business> {
    const location = (data.address ?? '').trim();
    if (!location) {
      throw new BadRequestException('address is required');
    }

    const business = this.businessRepo.create({
      name: data.name.trim(),
      type: data.type,
      description: data.description?.trim() || null,
      phone: data.phone?.trim() || null,
      eventServices: data.type === 'SERVICE' ? (data.eventServices ?? []) : [],
      documentUrl: data.documentUrl ?? null,
      cityId: data.cityId ?? null,
      location,
      serviceType:
        data.type === 'SERVICE' && data.serviceType
          ? data.serviceType
          : undefined,
      owner: { id: ownerId } as User,
      status: 'PENDING',
    });
    const saved = await this.businessRepo.save(business);
    await this.invalidateListCache(); // new listing must show in moderation
    return saved;
  }

  async getMyBusinesses(ownerId: string): Promise<Business[]> {
    return this.businessRepo.find({
      where: { owner: { id: ownerId } },
      order: { createdAt: 'DESC' },
    });
  }

  async getById(id: string): Promise<Business> {
    const business = await this.businessRepo.findOne({
      where: { id },
      relations: ['owner'],
    });
    if (!business) throw new NotFoundException('Business not found');
    return business;
  }

  // ── Admin: moderation (portal only) ────────────────────────────────────────

  async adminListAll(status?: string): Promise<Business[]> {
    const cacheKey = `${BusinessesService.LIST_CACHE_PREFIX}:${status ?? 'all'}`;
    const cached = await this.redisService.get(cacheKey);
    if (cached) return JSON.parse(cached) as Business[];

    const where: any = {};
    if (status) where.status = status;
    const rows = await this.businessRepo.find({
      where,
      relations: ['owner'],
      order: { createdAt: 'DESC' },
    });

    // Plain-object cache bypasses the serializer — strip owner private fields.
    const list = stripPrivateFields(rows);
    await this.redisService
      .set(cacheKey, JSON.stringify(list), 60)
      .catch(() => {});
    return list;
  }

  async adminSetStatus(
    id: string,
    status: 'VERIFIED' | 'REJECTED' | 'PENDING',
  ): Promise<Business> {
    const business = await this.getById(id);
    business.status = status;
    const saved = await this.businessRepo.save(business);
    await this.invalidateListCache();
    return saved;
  }

  // SECURITY FIX: only the business owner may manage operators/calendar.
  private async getOwned(
    businessId: string,
    requesterId: string,
  ): Promise<Business> {
    const business = await this.getById(businessId); // loads ['owner']
    if (business.owner?.id !== requesterId) {
      throw new ForbiddenException('You do not own this business');
    }
    return business;
  }

  async addOperator(
    businessId: string,
    userId: string,
    requesterId: string,
  ): Promise<Business> {
    const business = await this.getOwned(businessId, requesterId);
    const ops = business.operatorIds || [];
    if (!ops.includes(userId)) {
      ops.push(userId);
      business.operatorIds = ops;
      return this.businessRepo.save(business);
    }
    return business;
  }

  async addOfflineDay(
    businessId: string,
    dateIsoString: string,
    requesterId: string,
  ): Promise<Business> {
    const business = await this.getOwned(businessId, requesterId);
    const days = business.offlineDays || [];
    if (!days.includes(dateIsoString)) {
      days.push(dateIsoString);
      business.offlineDays = days;
      return this.businessRepo.save(business);
    }
    return business;
  }

  async removeOfflineDay(
    businessId: string,
    dateIsoString: string,
    requesterId: string,
  ): Promise<Business> {
    const business = await this.getOwned(businessId, requesterId);
    const days = business.offlineDays || [];
    const next = days.filter((d) => d !== dateIsoString);
    if (next.length !== days.length) {
      business.offlineDays = next;
      return this.businessRepo.save(business);
    }
    return business;
  }
}
