import {
  Injectable,
  Logger,
  OnModuleInit,
  OnModuleDestroy,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, RedisClientType } from 'redis';
import { buildRedisUrl } from './redis-url';
import { redisAllowsMemoryFallback } from './redis-fallback';

export interface LocationCache {
  lat: number;
  lng: number;
  timestamp: string;
}

/**
 * RedisService — all Redis access for the app.
 *
 * When Redis is unreachable, methods may degrade to a process-local store
 * ONLY if {@link redisAllowsMemoryFallback} is true (local single-process
 * dev). With `replicas: 2`, a silent memory store splits OTP, locks, and
 * caches across instances — so production / compose sets
 * `REDIS_ALLOW_MEMORY_FALLBACK=false` and Redis outages fail closed.
 *
 * Bull delayed jobs always need a real Redis regardless.
 */
@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private client: RedisClientType;
  private fallbackAnnounced = false;
  private readonly allowMemoryFallback: boolean;

  // Key namespaces
  private static readonly WORKER_SNAPSHOT = 'worker:snapshot:';
  private static readonly SKILL_INDEX = 'skill:index:';
  private static readonly GEO_INDEX = 'workers:geo';

  /** Max keys the admin key browser will collect in one scan. */
  private static readonly ADMIN_KEYS_LIMIT = 1000;

  // ── In-memory fallback stores (used only when Redis is unreachable) ──
  private memKv = new Map<
    string,
    { value: string; expiresAt: number | null }
  >();
  private memSets = new Map<string, Set<string>>();
  private memZsets = new Map<string, Map<string, number>>(); // member → score
  private memGeo = new Map<string, { lat: number; lng: number }>(); // member → coords
  private memKeyExp = new Map<string, number>(); // key-level TTL for sets/zsets

  constructor(private configService: ConfigService) {
    this.allowMemoryFallback = redisAllowsMemoryFallback(configService);

    // Capped exponential backoff so a missing Redis doesn't spam reconnects
    const socket = {
      reconnectStrategy: (retries: number) => Math.min(retries * 500, 30_000),
    };

    this.client = createClient({
      url: buildRedisUrl(this.configService),
      socket,
    });

    this.client.on('error', (err) => {
      // Log once per outage, not per failed command
      if (!this.fallbackAnnounced) {
        this.logger.warn(
          this.allowMemoryFallback
            ? `Redis unreachable (${err?.message ?? err}) — using in-memory fallback until it returns`
            : `Redis unreachable (${err?.message ?? err}) — memory fallback disabled; commands will fail closed`,
        );
        this.fallbackAnnounced = true;
      }
    });
    this.client.on('ready', () => {
      this.fallbackAnnounced = false;
      this.logger.log('Redis connected successfully');
    });
  }

  /** True when process-local memory may stand in for Redis (single-process dev). */
  allowsMemoryFallback(): boolean {
    return this.allowMemoryFallback;
  }

  /**
   * Call before touching mem* stores. Throws when fallback is disabled so
   * multi-replica deploys never silently split OTP / locks / caches.
   */
  private assertMemoryFallbackAllowed(op: string): void {
    if (this.allowMemoryFallback) return;
    throw new ServiceUnavailableException(
      `Redis unavailable for ${op} (in-memory fallback disabled)`,
    );
  }

  /** True when commands can actually be sent to Redis. */
  private get live(): boolean {
    return this.client?.isReady ?? false;
  }

  /** Public readiness for health badges (Monitoring page). */
  isReady(): boolean {
    return this.live;
  }

  /** Lightweight PING for health checks. False when using in-memory fallback. */
  async ping(): Promise<boolean> {
    if (!this.live) return false;
    try {
      const pong = await this.client.ping();
      return pong === 'PONG';
    } catch {
      return false;
    }
  }

  /**
   * Cache-effectiveness stats from INFO — powers the Monitoring page.
   * hitRatio > 0.9 is healthy; evictedKeys must stay 0 (noeviction policy —
   * a rising value means the policy was changed and Bull jobs are at risk);
   * usedMemoryPct nearing 100 with noeviction means writes will start
   * failing — time to split cache onto a second instance.
   * Null when Redis is unreachable (in-memory fallback active).
   */
  async getCacheStats(): Promise<{
    hits: number;
    misses: number;
    hitRatio: number | null;
    usedMemoryBytes: number;
    maxMemoryBytes: number;
    usedMemoryPct: number | null;
    evictedKeys: number;
    connectedClients: number;
    opsPerSec: number;
  } | null> {
    if (!this.live) return null;
    try {
      const [stats, memory, clients] = await Promise.all([
        this.client.info('stats'),
        this.client.info('memory'),
        this.client.info('clients'),
      ]);
      const num = (blob: string, field: string): number => {
        const m = blob.match(new RegExp(`^${field}:(\\d+)`, 'm'));
        return m ? Number(m[1]) : 0;
      };
      const hits = num(stats, 'keyspace_hits');
      const misses = num(stats, 'keyspace_misses');
      const usedMemoryBytes = num(memory, 'used_memory');
      const maxMemoryBytes = num(memory, 'maxmemory');
      return {
        hits,
        misses,
        hitRatio:
          hits + misses > 0
            ? Math.round((hits / (hits + misses)) * 1000) / 1000
            : null,
        usedMemoryBytes,
        maxMemoryBytes,
        usedMemoryPct:
          maxMemoryBytes > 0
            ? Math.round((usedMemoryBytes / maxMemoryBytes) * 1000) / 10
            : null,
        evictedKeys: num(stats, 'evicted_keys'),
        connectedClients: num(clients, 'connected_clients'),
        opsPerSec: num(stats, 'instantaneous_ops_per_sec'),
      };
    } catch (error) {
      this.logger.error('Redis INFO stats failed', error);
      return null;
    }
  }

  async onModuleInit() {
    try {
      await this.client.connect();
    } catch (error) {
      if (!this.allowMemoryFallback) {
        this.logger.error(
          'Could not connect to Redis and REDIS_ALLOW_MEMORY_FALLBACK is off — refusing to boot',
        );
        throw error;
      }
      this.logger.warn(
        'Could not connect to Redis — running on the in-memory fallback. ' +
          'Start Redis (docker compose up redis) for multi-instance/persistent state.',
      );
    }
  }

  async onModuleDestroy() {
    try {
      if (this.client.isOpen) await this.client.quit();
    } catch {
      // already disconnected — nothing to clean up
    }
  }

  // ─────────────────────────────────────────────
  // IN-MEMORY FALLBACK PRIMITIVES
  // ─────────────────────────────────────────────

  private memGet(key: string): string | null {
    const entry = this.memKv.get(key);
    if (!entry) return null;
    if (entry.expiresAt !== null && entry.expiresAt < Date.now()) {
      this.memKv.delete(key);
      return null;
    }
    return entry.value;
  }

  private memSet(key: string, value: string, ttlSeconds?: number): void {
    this.memKv.set(key, {
      value,
      expiresAt: ttlSeconds ? Date.now() + ttlSeconds * 1000 : null,
    });
  }

  private memKeyAlive(key: string): boolean {
    const exp = this.memKeyExp.get(key);
    if (exp !== undefined && exp < Date.now()) {
      this.memSets.delete(key);
      this.memZsets.delete(key);
      this.memKeyExp.delete(key);
      return false;
    }
    return true;
  }

  private static haversineKm(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
    const R = 6371;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  // ─────────────────────────────────────────────
  // GENERIC CACHE METHODS
  // ─────────────────────────────────────────────

  async get(key: string): Promise<string | null> {
    if (this.live) {
      try {
        return await this.client.get(key);
      } catch (error) {
        this.logger.error(`Redis GET failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('GET');
    return this.memGet(key);
  }

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (this.live) {
      try {
        if (ttlSeconds) {
          await this.client.setEx(key, ttlSeconds, value);
        } else {
          await this.client.set(key, value);
        }
        return;
      } catch (error) {
        this.logger.error(`Redis SET failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SET');
    this.memSet(key, value, ttlSeconds);
  }

  async del(...keys: string[]): Promise<void> {
    if (this.live) {
      try {
        await this.client.del(keys);
        return;
      } catch (error) {
        this.logger.error(`Redis DEL failed for keys: ${keys}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('DEL');
    for (const key of keys) {
      this.memKv.delete(key);
      this.memSets.delete(key);
      this.memZsets.delete(key);
      this.memKeyExp.delete(key);
    }
  }

  /**
   * SCAN, not KEYS: KEYS is O(N) over the whole keyspace and blocks Redis's
   * single thread — called from clearCache() on every master-entry admin
   * save, it would stall dispatch/polls as the keyspace grows. SCAN iterates
   * in small non-blocking batches. `limit` caps how many keys are collected;
   * pass 0 for no cap.
   */
  private async scanKeys(pattern: string, limit = 0): Promise<string[]> {
    const found: string[] = [];
    for await (const batch of this.client.scanIterator({
      MATCH: pattern,
      COUNT: 200,
    })) {
      // node-redis v4 yields single keys; v5 yields arrays — handle both.
      if (Array.isArray(batch)) found.push(...batch);
      else found.push(batch as string);
      if (limit > 0 && found.length >= limit) return found.slice(0, limit);
    }
    return found;
  }

  async keys(pattern: string): Promise<string[]> {
    if (this.live) {
      try {
        return await this.scanKeys(pattern);
      } catch (error) {
        this.logger.error(`Redis SCAN failed for pattern: ${pattern}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('KEYS');
    // Glob → regex (only * supported, which is all we use)
    const regex = new RegExp(
      '^' +
        pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') +
        '$',
    );
    const result: string[] = [];
    for (const key of this.memKv.keys()) {
      if (regex.test(key) && this.memGet(key) !== null) result.push(key);
    }
    return result;
  }

  /**
   * Best-effort single-runner lock (SET NX EX). Returns true to exactly one
   * caller across all replicas until `ttlSeconds` elapses. The lock is never
   * released early — it is sized to the work it guards, so a crashed holder
   * costs one skipped cycle rather than a permanent stall.
   *
   * When memory fallback is disabled and Redis is down, returns false (skip
   * the guarded work) instead of granting every replica a local lock.
   * When fallback is allowed, degrades to per-process locking — only safe
   * for single-process local dev and idempotent work.
   */
  async acquireLock(key: string, ttlSeconds: number): Promise<boolean> {
    if (this.live) {
      try {
        const res = await this.client.set(key, '1', {
          NX: true,
          EX: ttlSeconds,
        });
        return res === 'OK';
      } catch (error) {
        this.logger.error(`Redis lock failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) return false;
      }
    } else if (!this.allowMemoryFallback) {
      return false;
    }
    if (this.memGet(key) !== null) return false;
    this.memSet(key, '1', ttlSeconds);
    return true;
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
    await this.set(key, otp, TTL_SECONDS);
  }

  /** Retrieve an OTP (non-destructive — prefer {@link consumeOtp} for verify). */
  async getOtp(key: string): Promise<string | null> {
    return this.get(key);
  }

  /**
   * Atomically read-and-delete an OTP (Redis GETDEL).
   * Closes the get-then-delete replay window: only one concurrent caller
   * receives the value; a second verify with the same code sees null.
   * Wrong submissions also consume the code — caller must request a new OTP.
   */
  async consumeOtp(key: string): Promise<string | null> {
    if (this.live) {
      try {
        return await this.client.getDel(key);
      } catch (error) {
        this.logger.error(`Redis GETDEL failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('GETDEL');
    const value = this.memGet(key);
    if (value !== null) this.memKv.delete(key);
    return value;
  }

  /** Delete an OTP (e.g. after booking arrival/completion gate). */
  async deleteOtp(key: string): Promise<void> {
    await this.del(key);
  }

  // ─────────────────────────────────────────────
  // BOOKING STATUS CACHE (for lightweight polling)
  // ─────────────────────────────────────────────

  /**
   * Cache the current booking status in Redis.
   * Called on every status transition so the poll endpoint never hits the DB.
   */
  async cacheBookingStatus(
    bookingId: string,
    statusData: Record<string, any>,
  ): Promise<void> {
    // 24h TTL — stale entries auto-clean
    await this.set(
      `booking:status:${bookingId}`,
      JSON.stringify(statusData),
      24 * 60 * 60,
    );
  }

  /**
   * Read cached booking status from Redis.
   * Returns null if not cached (caller should fall back to DB).
   */
  async getCachedBookingStatus(
    bookingId: string,
  ): Promise<Record<string, any> | null> {
    const data = await this.get(`booking:status:${bookingId}`);
    try {
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // WORKER LOCATION CACHE
  // ─────────────────────────────────────────────

  /** Cache a worker's last known location. */
  async updateWorkerLocation(
    workerId: string,
    lat: number,
    lng: number,
  ): Promise<void> {
    const payload: LocationCache = {
      lat,
      lng,
      timestamp: new Date().toISOString(),
    };
    // 1. Save literal location for record lookup
    await this.set(
      `worker:location:${workerId}`,
      JSON.stringify(payload),
      60 * 60,
    );
    // 2. Save to GEO index for spatial search
    await this.updateWorkerGeoLocation(workerId, lat, lng);
  }

  /** Get a worker's last known location. */
  async getWorkerLocation(workerId: string): Promise<LocationCache | null> {
    const data = await this.get(`worker:location:${workerId}`);
    try {
      if (data) return JSON.parse(data) as LocationCache;
    } catch {
      return null;
    }
    return null;
  }

  // ─────────────────────────────────────────────
  // FCM TOKEN CACHE (7-DAY TTL)
  // ─────────────────────────────────────────────

  async cacheFcmToken(userId: string, token: string): Promise<void> {
    await this.set(`user:fcm:${userId}`, token, 7 * 24 * 60 * 60);
  }

  async getCachedFcmToken(userId: string): Promise<string | null> {
    return this.get(`user:fcm:${userId}`);
  }

  // ─────────────────────────────────────────────
  // WORKER GEO INDEXING
  // ─────────────────────────────────────────────

  /** Add/update a worker in the GEO index. */
  async updateWorkerGeoLocation(
    workerId: string,
    lat: number,
    lng: number,
  ): Promise<void> {
    if (this.live) {
      try {
        await this.client.geoAdd(RedisService.GEO_INDEX, {
          longitude: lng,
          latitude: lat,
          member: workerId,
        });
        return;
      } catch (error) {
        this.logger.error(
          `Failed to update geo location for worker ${workerId}`,
          error,
        );
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('GEOADD');
    this.memGeo.set(workerId, { lat, lng });
  }

  /**
   * Remove ONE worker from the GEO index (e.g. when going offline).
   * GEO sets are sorted sets under the hood, so ZREM removes the member —
   * this replaces the old (buggy) DEL of the entire index.
   */
  async removeWorkerFromGeoIndex(workerId: string): Promise<void> {
    if (this.live) {
      try {
        await this.client.zRem(RedisService.GEO_INDEX, workerId);
        return;
      } catch (error) {
        this.logger.error(
          `Failed to remove worker ${workerId} from geo index`,
          error,
        );
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZREM');
    this.memGeo.delete(workerId);
  }

  /**
   * Spatial query: IDs of all workers within radiusKm of (lat, lng).
   * Uses Redis GEOSEARCH when live, haversine over the fallback store
   * otherwise. Returns null if the query could not be executed at all —
   * callers should treat null as "no geo filter available" and fall back
   * to their own distance filtering.
   */
  async searchNearbyWorkerIds(
    lat: number,
    lng: number,
    radiusKm: number,
  ): Promise<string[] | null> {
    if (this.live) {
      try {
        const members = await this.client.geoSearch(
          RedisService.GEO_INDEX,
          { longitude: lng, latitude: lat },
          { radius: radiusKm, unit: 'km' },
        );
        return members as string[];
      } catch (error) {
        this.logger.error('Redis GEOSEARCH failed', error);
        return null;
      }
    }
    if (!this.allowMemoryFallback) return null;
    const result: string[] = [];
    for (const [workerId, coords] of this.memGeo) {
      if (
        RedisService.haversineKm(lat, lng, coords.lat, coords.lng) <= radiusKm
      ) {
        result.push(workerId);
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────
  // PENDING BOOKINGS (DISCOVERY)
  // ─────────────────────────────────────────────

  /**
   * Adds a booking ID to the worker's pending requests.
   * Uses a Sorted Set where score is the timestamp (allows DESC ordering).
   */
  async addPendingBooking(workerId: string, bookingId: string): Promise<void> {
    const key = `worker:pending:${workerId}`;
    if (this.live) {
      try {
        await this.client.zAdd(key, { score: Date.now(), value: bookingId });
        // 90s timeout matches the queue delay
        await this.client.expire(key, 120);
        return;
      } catch (error) {
        this.logger.error(
          `Failed to add pending booking ${bookingId} for worker ${workerId}`,
          error,
        );
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZADD');
    const zset = this.memZsets.get(key) ?? new Map<string, number>();
    zset.set(bookingId, Date.now());
    this.memZsets.set(key, zset);
    this.memKeyExp.set(key, Date.now() + 120 * 1000);
  }

  /** Removes a booking ID from the worker's pending requests. */
  async removePendingBooking(
    workerId: string,
    bookingId: string,
  ): Promise<void> {
    const key = `worker:pending:${workerId}`;
    if (this.live) {
      try {
        await this.client.zRem(key, bookingId);
        return;
      } catch (error) {
        this.logger.error(
          `Failed to remove pending booking ${bookingId} for worker ${workerId}`,
          error,
        );
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZREM');
    this.memZsets.get(key)?.delete(bookingId);
  }

  /** Caches that a worker rejected a request for 15 minutes to avoid second-round pings */
  async markWorkerRejectedJob(
    customerId: string,
    skill: string,
    workerId: string,
  ): Promise<void> {
    const key = `rejected:${customerId}:${skill}`;
    if (this.live) {
      try {
        await this.client.sAdd(key, workerId);
        await this.client.expire(key, 900); // 15 mins
        return;
      } catch (error) {
        this.logger.error(`Failed to set rejected cache ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SADD');
    const memSet = this.memSets.get(key) || new Set<string>();
    memSet.add(workerId);
    this.memSets.set(key, memSet);
    this.memKeyExp.set(key, Date.now() + 900 * 1000);
  }

  async getRejectedWorkersForJob(
    customerId: string,
    skill: string,
  ): Promise<string[]> {
    const key = `rejected:${customerId}:${skill}`;
    if (this.live) {
      try {
        return await this.client.sMembers(key);
      } catch (error) {
        this.logger.error(`Failed to get rejected cache ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SMEMBERS');
    if (!this.memKeyAlive(key)) return [];
    return Array.from(this.memSets.get(key) || []);
  }

  /** Gets all pending booking IDs for a worker, newest first. */
  async getPendingBookingIds(workerId: string): Promise<string[]> {
    const key = `worker:pending:${workerId}`;
    if (this.live) {
      try {
        // ZREVRANGE (highest score first)
        return await this.client.zRange(key, 0, -1, { REV: true });
      } catch (error) {
        this.logger.error(
          `Failed to get pending bookings for worker ${workerId}`,
          error,
        );
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZRANGE');
    if (!this.memKeyAlive(key)) return [];
    const zset = this.memZsets.get(key);
    if (!zset) return [];
    return [...zset.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([member]) => member);
  }

  // ─────────────────────────────────────────────
  // WORKER METADATA SNAPSHOT (SEARCH OPTIMIZATION)
  // ─────────────────────────────────────────────

  /** Caches the full WorkerDto as a JSON snapshot for instant discovery. */
  async cacheWorkerSnapshot(workerId: string, snapshot: any): Promise<void> {
    await this.set(
      `${RedisService.WORKER_SNAPSHOT}${workerId}`,
      JSON.stringify(snapshot),
      24 * 60 * 60,
    ); // 24h cache
  }

  /** Retrieves a cached worker snapshot. */
  async getWorkerSnapshot(workerId: string): Promise<any | null> {
    const data = await this.get(`${RedisService.WORKER_SNAPSHOT}${workerId}`);
    try {
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  }

  /** Maps workers to skills for ultra-fast filtering. */
  async indexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    for (const skill of skills) {
      const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
      if (this.live) {
        try {
          await this.client.sAdd(key, workerId);
          await this.client.expire(key, 24 * 60 * 60);
          continue;
        } catch (error) {
          this.logger.error(
            `Failed to index skill ${skill} for worker ${workerId}`,
            error,
          );
          if (!this.allowMemoryFallback) throw error;
        }
      }
      this.assertMemoryFallbackAllowed('SADD');
      const set = this.memSets.get(key) ?? new Set<string>();
      set.add(workerId);
      this.memSets.set(key, set);
      this.memKeyExp.set(key, Date.now() + 24 * 60 * 60 * 1000);
    }
  }

  /** Removes worker from skill indices. */
  async unindexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    for (const skill of skills) {
      const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
      if (this.live) {
        try {
          await this.client.sRem(key, workerId);
          continue;
        } catch (error) {
          this.logger.error(
            `Failed to unindex skill ${skill} for worker ${workerId}`,
            error,
          );
          if (!this.allowMemoryFallback) throw error;
        }
      }
      this.assertMemoryFallbackAllowed('SREM');
      this.memSets.get(key)?.delete(workerId);
    }
  }

  /** Returns IDs of all active workers who have a specific skill. */
  async getWorkerIdsBySkill(skill: string): Promise<string[]> {
    const key = `${RedisService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
    if (this.live) {
      try {
        return await this.client.sMembers(key);
      } catch (error) {
        this.logger.error(`Failed to get workers for skill ${skill}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SMEMBERS');
    if (!this.memKeyAlive(key)) return [];
    return [...(this.memSets.get(key) ?? [])];
  }

  // ── Admin Endpoints ──

  /**
   * Key browser for the admin monitoring page. Capped SCAN rather than KEYS:
   * this runs against production Redis on demand, and a default `*` KEYS over
   * the live keyspace blocks the server for every other caller.
   */
  async getAdminKeys(
    pattern: string = '*',
    limit: number = RedisService.ADMIN_KEYS_LIMIT,
  ): Promise<string[]> {
    if (!this.live) return [];
    try {
      return await this.scanKeys(pattern, limit);
    } catch (error) {
      this.logger.error('Failed to get Redis keys', error);
      return [];
    }
  }

  async getAdminKeyDetails(key: string): Promise<any> {
    if (!this.live) return null;
    try {
      const type = await this.client.type(key);
      const ttl = await this.client.ttl(key);
      let value: any = null;

      switch (type) {
        case 'string':
          value = await this.client.get(key);
          break;
        case 'hash':
          value = await this.client.hGetAll(key);
          break;
        case 'set':
          value = await this.client.sMembers(key);
          break;
        case 'zset':
          value = await this.client.zRangeWithScores(key, 0, -1);
          break;
        case 'list':
          value = await this.client.lRange(key, 0, -1);
          break;
        default:
          value = `Cannot fetch value for type: ${type}`;
      }

      return { key, type, ttl, value };
    } catch (error) {
      this.logger.error(`Failed to get details for Redis key ${key}`, error);
      return { key, type: 'error', ttl: -1, value: null };
    }
  }
}
