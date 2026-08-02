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
import { RedisBookingStateService } from './redis-booking-state.service';
import {
  LocationCache,
  RedisWorkerIndexService,
} from './redis-worker-index.service';
import { RedisAdminService } from './redis-admin.service';

export type { LocationCache } from './redis-worker-index.service';

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

  private static readonly GEO_INDEX = 'workers:geo';

  // ── In-memory fallback stores (used only when Redis is unreachable) ──
  private memKv = new Map<
    string,
    { value: string; expiresAt: number | null }
  >();
  private memSets = new Map<string, Set<string>>();
  private memZsets = new Map<string, Map<string, number>>(); // member → score
  private memGeo = new Map<string, { lat: number; lng: number }>(); // member → coords
  private memKeyExp = new Map<string, number>(); // key-level TTL for sets/zsets
  private _bookingState?: RedisBookingStateService;
  private _workerIndex?: RedisWorkerIndexService;
  private _admin?: RedisAdminService;

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

  async getDel(key: string): Promise<string | null> {
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

  async sAdd(key: string, member: string, ttlSeconds?: number): Promise<void> {
    if (this.live) {
      try {
        await this.client.sAdd(key, member);
        if (ttlSeconds) await this.client.expire(key, ttlSeconds);
        return;
      } catch (error) {
        this.logger.error(`Redis SADD failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SADD');
    const set = this.memSets.get(key) ?? new Set<string>();
    set.add(member);
    this.memSets.set(key, set);
    if (ttlSeconds) {
      this.memKeyExp.set(key, Date.now() + ttlSeconds * 1000);
    }
  }

  async sRem(key: string, member: string): Promise<void> {
    if (this.live) {
      try {
        await this.client.sRem(key, member);
        return;
      } catch (error) {
        this.logger.error(`Redis SREM failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SREM');
    this.memSets.get(key)?.delete(member);
  }

  async sMembers(key: string): Promise<string[]> {
    if (this.live) {
      try {
        return await this.client.sMembers(key);
      } catch (error) {
        this.logger.error(`Redis SMEMBERS failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('SMEMBERS');
    if (!this.memKeyAlive(key)) return [];
    return [...(this.memSets.get(key) ?? [])];
  }

  async zAdd(
    key: string,
    score: number,
    member: string,
    ttlSeconds?: number,
  ): Promise<void> {
    if (this.live) {
      try {
        await this.client.zAdd(key, { score, value: member });
        if (ttlSeconds) await this.client.expire(key, ttlSeconds);
        return;
      } catch (error) {
        this.logger.error(`Redis ZADD failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZADD');
    const zset = this.memZsets.get(key) ?? new Map<string, number>();
    zset.set(member, score);
    this.memZsets.set(key, zset);
    if (ttlSeconds) {
      this.memKeyExp.set(key, Date.now() + ttlSeconds * 1000);
    }
  }

  async zRem(key: string, member: string): Promise<void> {
    if (this.live) {
      try {
        await this.client.zRem(key, member);
        return;
      } catch (error) {
        this.logger.error(`Redis ZREM failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZREM');
    this.memZsets.get(key)?.delete(member);
  }

  async zRangeRev(key: string): Promise<string[]> {
    if (this.live) {
      try {
        return await this.client.zRange(key, 0, -1, { REV: true });
      } catch (error) {
        this.logger.error(`Redis ZRANGE failed for key: ${key}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZRANGE');
    if (!this.memKeyAlive(key)) return [];
    return [...(this.memZsets.get(key)?.entries() ?? [])]
      .sort((a, b) => b[1] - a[1])
      .map(([member]) => member);
  }

  async geoAdd(member: string, lat: number, lng: number): Promise<void> {
    if (this.live) {
      try {
        await this.client.geoAdd(RedisService.GEO_INDEX, {
          longitude: lng,
          latitude: lat,
          member,
        });
        return;
      } catch (error) {
        this.logger.error(`Redis GEOADD failed for member: ${member}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('GEOADD');
    this.memGeo.set(member, { lat, lng });
  }

  async geoRem(member: string): Promise<void> {
    if (this.live) {
      try {
        await this.client.zRem(RedisService.GEO_INDEX, member);
        return;
      } catch (error) {
        this.logger.error(`Redis GEO ZREM failed for member: ${member}`, error);
        if (!this.allowMemoryFallback) throw error;
      }
    }
    this.assertMemoryFallbackAllowed('ZREM');
    this.memGeo.delete(member);
  }

  async geoSearch(
    lat: number,
    lng: number,
    radiusKm: number,
  ): Promise<string[] | null> {
    if (this.live) {
      try {
        return (await this.client.geoSearch(
          RedisService.GEO_INDEX,
          { longitude: lng, latitude: lat },
          { radius: radiusKm, unit: 'km' },
        )) as string[];
      } catch (error) {
        this.logger.error('Redis GEOSEARCH failed', error);
        return null;
      }
    }
    if (!this.allowMemoryFallback) return null;
    const result: string[] = [];
    for (const [member, coords] of this.memGeo) {
      if (
        RedisService.haversineKm(lat, lng, coords.lat, coords.lng) <= radiusKm
      ) {
        result.push(member);
      }
    }
    return result;
  }

  /**
   * SCAN, not KEYS: KEYS is O(N) over the whole keyspace and blocks Redis's
   * single thread — called from clearCache() on every master-entry admin
   * save, it would stall dispatch/polls as the keyspace grows. SCAN iterates
   * in small non-blocking batches. `limit` caps how many keys are collected;
   * pass 0 for no cap.
   */
  async scanKeysLimited(pattern: string, limit = 0): Promise<string[]> {
    if (!this.live) {
      this.assertMemoryFallbackAllowed('SCAN');
      return (await this.keys(pattern)).slice(0, limit > 0 ? limit : undefined);
    }
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
        return await this.scanKeysLimited(pattern);
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

  async inspectKey(key: string): Promise<any> {
    if (!this.live) return null;
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

  private bookingState(): RedisBookingStateService {
    return (this._bookingState ??= new RedisBookingStateService(this));
  }

  private workerIndex(): RedisWorkerIndexService {
    return (this._workerIndex ??= new RedisWorkerIndexService(this));
  }

  private admin(): RedisAdminService {
    return (this._admin ??= new RedisAdminService(this));
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
    return this.bookingState().saveOtp(key, otp);
  }

  /** Retrieve an OTP (non-destructive — prefer {@link consumeOtp} for verify). */
  async getOtp(key: string): Promise<string | null> {
    return this.bookingState().getOtp(key);
  }

  /**
   * Atomically read-and-delete an OTP (Redis GETDEL).
   * Closes the get-then-delete replay window: only one concurrent caller
   * receives the value; a second verify with the same code sees null.
   * Wrong submissions also consume the code — caller must request a new OTP.
   */
  async consumeOtp(key: string): Promise<string | null> {
    return this.bookingState().consumeOtp(key);
  }

  /** Delete an OTP (e.g. after booking arrival/completion gate). */
  async deleteOtp(key: string): Promise<void> {
    return this.bookingState().deleteOtp(key);
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
    return this.bookingState().cacheBookingStatus(bookingId, statusData);
  }

  /**
   * Read cached booking status from Redis.
   * Returns null if not cached (caller should fall back to DB).
   */
  async getCachedBookingStatus(
    bookingId: string,
  ): Promise<Record<string, any> | null> {
    return this.bookingState().getCachedBookingStatus(bookingId);
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
    return this.workerIndex().updateWorkerLocation(workerId, lat, lng);
  }

  /** Get a worker's last known location. */
  async getWorkerLocation(workerId: string): Promise<LocationCache | null> {
    return this.workerIndex().getWorkerLocation(workerId);
  }

  // ─────────────────────────────────────────────
  // FCM TOKEN CACHE (7-DAY TTL)
  // ─────────────────────────────────────────────

  async cacheFcmToken(userId: string, token: string): Promise<void> {
    return this.bookingState().cacheFcmToken(userId, token);
  }

  async getCachedFcmToken(userId: string): Promise<string | null> {
    return this.bookingState().getCachedFcmToken(userId);
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
    return this.workerIndex().updateWorkerGeoLocation(workerId, lat, lng);
  }

  /**
   * Remove ONE worker from the GEO index (e.g. when going offline).
   * GEO sets are sorted sets under the hood, so ZREM removes the member —
   * this replaces the old (buggy) DEL of the entire index.
   */
  async removeWorkerFromGeoIndex(workerId: string): Promise<void> {
    return this.workerIndex().removeWorkerFromGeoIndex(workerId);
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
    return this.workerIndex().searchNearbyWorkerIds(lat, lng, radiusKm);
  }

  // ─────────────────────────────────────────────
  // PENDING BOOKINGS (DISCOVERY)
  // ─────────────────────────────────────────────

  /**
   * Adds a booking ID to the worker's pending requests.
   * Uses a Sorted Set where score is the timestamp (allows DESC ordering).
   */
  async addPendingBooking(workerId: string, bookingId: string): Promise<void> {
    return this.bookingState().addPendingBooking(workerId, bookingId);
  }

  /** Removes a booking ID from the worker's pending requests. */
  async removePendingBooking(
    workerId: string,
    bookingId: string,
  ): Promise<void> {
    return this.bookingState().removePendingBooking(workerId, bookingId);
  }

  /** Caches that a worker rejected a request for 15 minutes to avoid second-round pings */
  async markWorkerRejectedJob(
    customerId: string,
    skill: string,
    workerId: string,
  ): Promise<void> {
    return this.bookingState().markWorkerRejectedJob(
      customerId,
      skill,
      workerId,
    );
  }

  async getRejectedWorkersForJob(
    customerId: string,
    skill: string,
  ): Promise<string[]> {
    return this.bookingState().getRejectedWorkersForJob(customerId, skill);
  }

  /** Gets all pending booking IDs for a worker, newest first. */
  async getPendingBookingIds(workerId: string): Promise<string[]> {
    return this.bookingState().getPendingBookingIds(workerId);
  }

  // ─────────────────────────────────────────────
  // WORKER METADATA SNAPSHOT (SEARCH OPTIMIZATION)
  // ─────────────────────────────────────────────

  /** Caches the full WorkerDto as a JSON snapshot for instant discovery. */
  async cacheWorkerSnapshot(workerId: string, snapshot: any): Promise<void> {
    return this.workerIndex().cacheWorkerSnapshot(workerId, snapshot);
  }

  /** Retrieves a cached worker snapshot. */
  async getWorkerSnapshot(workerId: string): Promise<any | null> {
    return this.workerIndex().getWorkerSnapshot(workerId);
  }

  /** Maps workers to skills for ultra-fast filtering. */
  async indexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    return this.workerIndex().indexWorkerSkills(workerId, skills);
  }

  /** Removes worker from skill indices. */
  async unindexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    return this.workerIndex().unindexWorkerSkills(workerId, skills);
  }

  /** Returns IDs of all active workers who have a specific skill. */
  async getWorkerIdsBySkill(skill: string): Promise<string[]> {
    return this.workerIndex().getWorkerIdsBySkill(skill);
  }

  // ── Admin Endpoints ──

  /**
   * Key browser for the admin monitoring page. Capped SCAN rather than KEYS:
   * this runs against production Redis on demand, and a default `*` KEYS over
   * the live keyspace blocks the server for every other caller.
   */
  async getAdminKeys(pattern = '*', limit = 1000): Promise<string[]> {
    return this.admin().getAdminKeys(pattern, limit);
  }

  async getAdminKeyDetails(key: string): Promise<any> {
    return this.admin().getAdminKeyDetails(key);
  }
}
