import { RedisService } from './redis.service';

/**
 * Unit tests for RedisService's IN-MEMORY FALLBACK path.
 *
 * In these tests `onModuleInit()` is never called and no Redis URL is
 * configured, so `client.isReady` is false → the private `live` getter is
 * false → every public method transparently degrades to its process-local
 * store. That fallback is real, shipped behaviour (it keeps the backend
 * functional — OTP login, dispatch, caches — on a machine with no Redis),
 * and it is pure, deterministic logic worth asserting:
 *   - kv get/set/del with TTL expiry, keys() glob→regex matching
 *   - OTP / booking-status / worker-location / FCM cache round-trips
 *   - geo indexing + haversine `searchNearbyWorkerIds` radius filter + removal
 *   - pending-booking sorted-set newest-first ordering + key TTL expiry
 *   - worker snapshot + case-insensitive skill index add/remove/query
 *
 * No real Redis client connects and no network/database is touched — the
 * `redis` client object is constructed but never `.connect()`-ed.
 */

/** ConfigService stub that returns undefined for every key → no REDIS_URL,
 *  so the constructor builds a localhost client that is never connected. */
function makeService(): RedisService {
  const config = { get: jest.fn((_key: string) => undefined) } as any;
  return new RedisService(config);
}

describe('RedisService (in-memory fallback)', () => {
  let svc: RedisService;

  beforeEach(() => {
    svc = makeService();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('generic kv (get/set/del)', () => {
    it('round-trips a value with no TTL', async () => {
      await svc.set('k', 'v');
      expect(await svc.get('k')).toBe('v');
    });

    it('returns null for a missing key', async () => {
      expect(await svc.get('nope')).toBeNull();
    });

    it('overwrites an existing value', async () => {
      await svc.set('k', 'one');
      await svc.set('k', 'two');
      expect(await svc.get('k')).toBe('two');
    });

    it('deletes a key (and tolerates deleting many at once)', async () => {
      await svc.set('a', '1');
      await svc.set('b', '2');
      await svc.del('a', 'b', 'never-existed');
      expect(await svc.get('a')).toBeNull();
      expect(await svc.get('b')).toBeNull();
    });

    it('expires a value once its TTL elapses', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());
      await svc.set('temp', 'v', 60); // 60s TTL
      expect(await svc.get('temp')).toBe('v');
      jest.advanceTimersByTime(61_000); // +61s
      expect(await svc.get('temp')).toBeNull();
    });
  });

  describe('keys() glob matching', () => {
    it('matches a trailing wildcard and excludes non-matching keys', async () => {
      await svc.set('user:fcm:1', 'a');
      await svc.set('user:fcm:2', 'b');
      await svc.set('booking:status:9', 'c');
      const matched = (await svc.keys('user:fcm:*')).sort();
      expect(matched).toEqual(['user:fcm:1', 'user:fcm:2']);
    });

    it('does not return expired keys', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());
      await svc.set('s:1', 'a', 30);
      await svc.set('s:2', 'b'); // no TTL
      jest.advanceTimersByTime(31_000);
      expect(await svc.keys('s:*')).toEqual(['s:2']);
    });
  });

  describe('OTP storage', () => {
    it('saves, reads, and deletes an OTP', async () => {
      await svc.saveOtp('otp:booking:1:arrival', '4821');
      expect(await svc.getOtp('otp:booking:1:arrival')).toBe('4821');
      await svc.deleteOtp('otp:booking:1:arrival');
      expect(await svc.getOtp('otp:booking:1:arrival')).toBeNull();
    });

    it('consumeOtp returns the value and removes it atomically', async () => {
      await svc.saveOtp('otp:auth:phone', '654321');
      expect(await svc.consumeOtp('otp:auth:phone')).toBe('654321');
      expect(await svc.consumeOtp('otp:auth:phone')).toBeNull();
      expect(await svc.getOtp('otp:auth:phone')).toBeNull();
    });

    it('expires an OTP after its 5-minute TTL', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());
      await svc.saveOtp('otp:x', '1234');
      jest.advanceTimersByTime(5 * 60 * 1000 + 1000); // 5m + 1s
      expect(await svc.getOtp('otp:x')).toBeNull();
    });
  });

  describe('booking status cache', () => {
    it('round-trips a status object as JSON', async () => {
      await svc.cacheBookingStatus('b1', { status: 'ACCEPTED', eta: 12 });
      expect(await svc.getCachedBookingStatus('b1')).toEqual({
        status: 'ACCEPTED',
        eta: 12,
      });
    });

    it('returns null when nothing is cached', async () => {
      expect(await svc.getCachedBookingStatus('missing')).toBeNull();
    });

    it('returns null when the cached payload is not valid JSON', async () => {
      await svc.set('booking:status:bad', '{not json');
      expect(await svc.getCachedBookingStatus('bad')).toBeNull();
    });
  });

  describe('worker location cache', () => {
    it('stores the literal location and also indexes it for geo search', async () => {
      await svc.updateWorkerLocation('w1', 12.9716, 77.5946);
      const loc = await svc.getWorkerLocation('w1');
      expect(loc?.lat).toBe(12.9716);
      expect(loc?.lng).toBe(77.5946);
      expect(typeof loc?.timestamp).toBe('string');
      // updateWorkerLocation also pushes to the geo index:
      const near = await svc.searchNearbyWorkerIds(12.9716, 77.5946, 1);
      expect(near).toContain('w1');
    });

    it('returns null for an unknown worker', async () => {
      expect(await svc.getWorkerLocation('ghost')).toBeNull();
    });
  });

  describe('FCM token cache', () => {
    it('caches and reads back a token', async () => {
      await svc.cacheFcmToken('u1', 'tok-abc');
      expect(await svc.getCachedFcmToken('u1')).toBe('tok-abc');
    });
  });

  describe('geo index + searchNearbyWorkerIds (haversine)', () => {
    it('includes workers inside the radius and excludes those outside', async () => {
      // Bangalore vs Chennai (~290 km apart)
      await svc.updateWorkerGeoLocation('blr', 12.9716, 77.5946);
      await svc.updateWorkerGeoLocation('maa', 13.0827, 80.2707);
      const near = await svc.searchNearbyWorkerIds(12.9716, 77.5946, 50);
      expect(near).toContain('blr');
      expect(near).not.toContain('maa');
    });

    it('returns an empty array when no workers are indexed', async () => {
      expect(await svc.searchNearbyWorkerIds(0, 0, 100)).toEqual([]);
    });

    it('removes a worker from the geo index', async () => {
      await svc.updateWorkerGeoLocation('w1', 12.9716, 77.5946);
      await svc.removeWorkerFromGeoIndex('w1');
      const near = await svc.searchNearbyWorkerIds(12.9716, 77.5946, 5);
      expect(near).not.toContain('w1');
    });
  });

  describe('pending bookings (sorted set)', () => {
    it('returns pending booking ids newest-first and supports removal', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());
      await svc.addPendingBooking('w1', 'b-old');
      jest.advanceTimersByTime(1000);
      await svc.addPendingBooking('w1', 'b-new');
      expect(await svc.getPendingBookingIds('w1')).toEqual(['b-new', 'b-old']);

      await svc.removePendingBooking('w1', 'b-old');
      expect(await svc.getPendingBookingIds('w1')).toEqual(['b-new']);
    });

    it('returns an empty list for a worker with no pending bookings', async () => {
      expect(await svc.getPendingBookingIds('nobody')).toEqual([]);
    });

    it('expires the pending set after its TTL', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());
      await svc.addPendingBooking('w1', 'b1');
      jest.advanceTimersByTime(121_000); // > 120s key TTL
      expect(await svc.getPendingBookingIds('w1')).toEqual([]);
    });
  });

  describe('worker snapshot cache', () => {
    it('round-trips a snapshot object', async () => {
      await svc.cacheWorkerSnapshot('w1', { name: 'Anu', rating: 4.8 });
      expect(await svc.getWorkerSnapshot('w1')).toEqual({
        name: 'Anu',
        rating: 4.8,
      });
    });

    it('returns null when no snapshot is cached', async () => {
      expect(await svc.getWorkerSnapshot('none')).toBeNull();
    });
  });

  describe('skill index', () => {
    it('indexes a worker under each skill (case-insensitive key) and queries it', async () => {
      await svc.indexWorkerSkills('w1', ['Plumbing', 'Electrician']);
      expect(await svc.getWorkerIdsBySkill('plumbing')).toContain('w1');
      expect(await svc.getWorkerIdsBySkill('ELECTRICIAN')).toContain('w1');
    });

    it('unindexes a worker from a skill', async () => {
      await svc.indexWorkerSkills('w1', ['Cleaning']);
      await svc.unindexWorkerSkills('w1', ['Cleaning']);
      expect(await svc.getWorkerIdsBySkill('cleaning')).not.toContain('w1');
    });

    it('returns an empty array for an unknown skill', async () => {
      expect(await svc.getWorkerIdsBySkill('astrophysics')).toEqual([]);
    });
  });
});
