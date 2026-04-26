import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, RedisClientType } from 'redis';

export interface LocationCache {
  lat: number;
  lng: number;
  timestamp: string;
}

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private client: RedisClientType;
  
  // Key namespaces
  private static readonly WORKER_SNAPSHOT = 'worker:snapshot:';
  private static readonly SKILL_INDEX = 'skill:index:';
  private static readonly GEO_INDEX = 'workers:geo';

  constructor(private configService: ConfigService) {
    const redisUrl = this.configService.get<string>('REDIS_URL');

    if (redisUrl) {
      this.client = createClient({ url: redisUrl });
    } else {
      const host = this.configService.get<string>('REDIS_HOST') || 'localhost';
      const port = this.configService.get<number>('REDIS_PORT') || 6379;
      const password = this.configService.get<string>('REDIS_PASSWORD');

      this.client = createClient({
        url: password
          ? `redis://:${password}@${host}:${port}`
          : `redis://${host}:${port}`,
      });
    }

    this.client.on('error', (err) =>
      this.logger.error('Redis Client Error', err),
    );
    this.client.on('connect', () =>
      this.logger.log('Redis connected successfully'),
    );
  }

  // ─────────────────────────────────────────────
  // GENERIC CACHE METHODS
  // ─────────────────────────────────────────────

  async get(key: string): Promise<string | null> {
    try {
      return await this.client.get(key);
    } catch (error) {
      this.logger.error(`Redis GET failed for key: ${key}`, error);
      return null;
    }
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    try {
      if (ttlSeconds) {
        await this.client.setEx(key, ttlSeconds, value);
      } else {
        await this.client.set(key, value);
      }
    } catch (error) {
      this.logger.error(`Redis SET failed for key: ${key}`, error);
    }
  }

  async del(...keys: string[]): Promise<void> {
    try {
      await this.client.del(keys);
    } catch (error) {
      this.logger.error(`Redis DEL failed for keys: ${keys}`, error);
    }
  }

  async keys(pattern: string): Promise<string[]> {
    try {
      return await this.client.keys(pattern);
    } catch (error) {
      this.logger.error(`Redis KEYS failed for pattern: ${pattern}`, error);
      return [];
    }
  }

  async onModuleInit() {
    try {
      await this.client.connect();
    } catch (error) {
      this.logger.error('Could not connect to Redis. Some features (OTP, Location Cache) will be unavailable.', error);
    }
  }

  async onModuleDestroy() {
    await this.client.quit();
  }

  // ─────────────────────────────────────────────
  // OTP STORAGE (5-MIN TTL)
  // ─────────────────────────────────────────────

  /**
   * Store an OTP for a specific combination of user/booking with a 5-minute expiry.
   * @param key e.g. "otp:booking:123:arrival"
   * @param otp The actual OTP string
   */
  async saveOtp(key: string, otp: string): Promise<void> {
    const TTL_SECONDS = 5 * 60; // 5 minutes
    try {
      await this.client.setEx(key, TTL_SECONDS, otp);
      this.logger.debug(`Saved OTP with key: ${key} (TTL: 5m)`);
    } catch (error) {
      this.logger.error(`Failed to save OTP to Redis: ${key}`, error);
    }
  }

  /**
   * Retrieve an OTP.
   */
  async getOtp(key: string): Promise<string | null> {
    try {
      return await this.client.get(key);
    } catch (error) {
      this.logger.error(`Failed to retrieve OTP from Redis: ${key}`, error);
      return null;
    }
  }

  /**
   * Delete an OTP after successful verification.
   */
  async deleteOtp(key: string): Promise<void> {
    try {
      await this.client.del(key);
    } catch (error) {
      this.logger.error(`Failed to delete OTP: ${key}`, error);
    }
  }

  // ─────────────────────────────────────────────
  // BOOKING STATUS CACHE (for lightweight polling)
  // ─────────────────────────────────────────────

  /**
   * Cache the current booking status in Redis.
   * Called on every status transition so the poll endpoint never hits the DB.
   */
  async cacheBookingStatus(bookingId: string, statusData: Record<string, any>): Promise<void> {
    const key = `booking:status:${bookingId}`;
    try {
      // 24h TTL — stale entries auto-clean
      await this.client.setEx(key, 24 * 60 * 60, JSON.stringify(statusData));
    } catch (error) {
      this.logger.error(`Failed to cache booking status: ${bookingId}`, error);
    }
  }

  /**
   * Read cached booking status from Redis.
   * Returns null if not cached (caller should fall back to DB).
   */
  async getCachedBookingStatus(bookingId: string): Promise<Record<string, any> | null> {
    const key = `booking:status:${bookingId}`;
    try {
      const data = await this.client.get(key);
      return data ? JSON.parse(data) : null;
    } catch (error) {
      this.logger.error(`Failed to get cached booking status: ${bookingId}`, error);
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // WORKER LOCATION CACHE
  // ─────────────────────────────────────────────

  /**
   * Cache a worker's last known location.
   */
  async updateWorkerLocation(workerId: string, lat: number, lng: number): Promise<void> {
    const key = `worker:location:${workerId}`;
    const payload: LocationCache = {
      lat,
      lng,
      timestamp: new Date().toISOString()
    };
    try {
      // 1. Save literal location for record lookup
      await this.client.setEx(key, 60 * 60, JSON.stringify(payload));
      // 2. Save to GEO index for spatial search
      await this.updateWorkerGeoLocation(workerId, lat, lng);
    } catch (error) {
      this.logger.error(`Failed to save location for worker ${workerId}`, error);
    }
  }

  /**
   * Get a worker's last known location.
   */
  async getWorkerLocation(workerId: string): Promise<LocationCache | null> {
    const key = `worker:location:${workerId}`;
    try {
      const data = await this.client.get(key);
      if (data) return JSON.parse(data) as LocationCache;
      return null;
    } catch (error) {
      this.logger.error(`Failed to get location for worker ${workerId}`, error);
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // FCM TOKEN CACHE (7-DAY TTL)
  // ─────────────────────────────────────────────

  async cacheFcmToken(userId: string, token: string): Promise<void> {
    const key = `user:fcm:${userId}`;
    try {
      await this.client.setEx(key, 7 * 24 * 60 * 60, token); // 7 days
    } catch (error) {
      this.logger.error(`Failed to cache FCM token for ${userId}`, error);
    }
  }

  async getCachedFcmToken(userId: string): Promise<string | null> {
    const key = `user:fcm:${userId}`;
    try {
      return await this.client.get(key);
    } catch (error) {
      this.logger.error(`Failed to get cached FCM token for ${userId}`, error);
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // WORKER GEO INDEXING
  // ─────────────────────────────────────────────

  /**
   * Execute a raw geographic spatial query natively via Redis GEO commands.
   */
  async updateWorkerGeoLocation(workerId: string, lat: number, lng: number): Promise<void> {
    try {
      await this.client.geoAdd('workers:geo', {
        longitude: lng,
        latitude: lat,
        member: workerId
      });
    } catch (error) {
      this.logger.error(`Failed to update geo location for worker ${workerId}`, error);
    }
  }

  // ─────────────────────────────────────────────
  // PENDING BOOKINGS (DISCOVERY)
  // ─────────────────────────────────────────────

  /**
   * Adds a booking ID to the worker's pending requests in Redis.
   * Uses a Sorted Set where score is the timestamp (allows DESC ordering).
   */
  async addPendingBooking(workerId: string, bookingId: string): Promise<void> {
    const key = `worker:pending:${workerId}`;
    try {
      await this.client.zAdd(key, {
        score: Date.now(),
        value: bookingId,
      });
      // 90s timeout matches the queue delay
      await this.client.expire(key, 120); 
    } catch (error) {
      this.logger.error(`Failed to add pending booking ${bookingId} for worker ${workerId}`, error);
    }
  }

  /**
   * Removes a booking ID from the worker's pending requests.
   */
  async removePendingBooking(workerId: string, bookingId: string): Promise<void> {
    const key = `worker:pending:${workerId}`;
    try {
      await this.client.zRem(key, bookingId);
    } catch (error) {
      this.logger.error(`Failed to remove pending booking ${bookingId} for worker ${workerId}`, error);
    }
  }

  /**
   * Gets all pending booking IDs for a worker, newest first.
   */
  async getPendingBookingIds(workerId: string): Promise<string[]> {
    const key = `worker:pending:${workerId}`;
    try {
      // ZREVRANGE (highest score first)
      return await this.client.zRange(key, 0, -1, { REV: true });
    } catch (error) {
      this.logger.error(`Failed to get pending bookings for worker ${workerId}`, error);
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // WORKER METADATA SNAPSHOT (SEARCH OPTIMIZATION)
  // ─────────────────────────────────────────────

  /**
   * Caches the full WorkerDto as a JSON snapshot for instant discovery.
   */
  async cacheWorkerSnapshot(workerId: string, snapshot: any): Promise<void> {
    const key = `${RedisService.WORKER_SNAPSHOT}${workerId}`;
    try {
      await this.client.setEx(key, 24 * 60 * 60, JSON.stringify(snapshot)); // 24h cache
    } catch (error) {
      this.logger.error(`Failed to cache snapshot for worker ${workerId}`, error);
    }
  }

  /**
   * Retrieves a cached worker snapshot.
   */
  async getWorkerSnapshot(workerId: string): Promise<any | null> {
    const key = `${RedisService.WORKER_SNAPSHOT}${workerId}`;
    try {
      const data = await this.client.get(key);
      return data ? JSON.parse(data) : null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Maps workers to skills for ultra-fast filtering.
   */
  async indexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    try {
      for (const skill of skills) {
        const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
        await this.client.sAdd(key, workerId);
        await this.client.expire(key, 24 * 60 * 60);
      }
    } catch (error) {
       this.logger.error(`Failed to index skills for worker ${workerId}`, error);
    }
  }

  /**
   * Removes worker from skill indices.
   */
  async unindexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    try {
      for (const skill of skills) {
        const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
        await this.client.sRem(key, workerId);
      }
    } catch (error) {
      this.logger.error(`Failed to unindex skills for worker ${workerId}`, error);
    }
  }

  /**
   * Returns IDs of all active workers who have a specific skill.
   */
  async getWorkerIdsBySkill(skill: string): Promise<string[]> {
    const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
    try {
      return await this.client.sMembers(key);
    } catch (error) {
      return [];
    }
  }
}
