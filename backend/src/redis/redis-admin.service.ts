import { forwardRef, Inject, Injectable, Logger } from '@nestjs/common';
import { RedisService } from './redis.service';

@Injectable()
export class RedisAdminService {
  private readonly logger = new Logger(RedisAdminService.name);
  private static readonly ADMIN_KEYS_LIMIT = 1000;

  constructor(
    @Inject(forwardRef(() => RedisService))
    private readonly redis: RedisService,
  ) {}

  async getAdminKeys(
    pattern = '*',
    limit = RedisAdminService.ADMIN_KEYS_LIMIT,
  ): Promise<string[]> {
    if (!this.redis.isReady()) return [];
    try {
      return await this.redis.scanKeysLimited(pattern, limit);
    } catch (error) {
      this.logger.error('Failed to get Redis keys', error);
      return [];
    }
  }

  async getAdminKeyDetails(key: string): Promise<any> {
    if (!this.redis.isReady()) return null;
    try {
      return await this.redis.inspectKey(key);
    } catch (error) {
      this.logger.error(`Failed to get details for Redis key ${key}`, error);
      return { key, type: 'error', ttl: -1, value: null };
    }
  }
}
