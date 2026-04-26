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
}
