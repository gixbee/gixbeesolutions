import { forwardRef, Inject, Injectable } from '@nestjs/common';
import { RedisService } from './redis.service';

@Injectable()
export class RedisBookingStateService {
  constructor(
    @Inject(forwardRef(() => RedisService))
    private readonly redis: RedisService,
  ) {}

  async saveOtp(key: string, otp: string): Promise<void> {
    await this.redis.set(key, otp, 5 * 60);
  }

  async getOtp(key: string): Promise<string | null> {
    return this.redis.get(key);
  }

  async consumeOtp(key: string): Promise<string | null> {
    return this.redis.getDel(key);
  }

  async deleteOtp(key: string): Promise<void> {
    await this.redis.del(key);
  }

  async cacheBookingStatus(
    bookingId: string,
    statusData: Record<string, any>,
  ): Promise<void> {
    // Merge-on-write: partial callers (cancel-request, GPS strike, etc.) must
    // not wipe arrivalOtp / phones / payment flags already in the cache.
    const existing = await this.getCachedBookingStatus(bookingId);
    const merged = { ...(existing ?? {}), ...statusData };
    // Explicit nulls in the patch clear keys (e.g. cancelRequested: false).
    for (const [key, value] of Object.entries(statusData)) {
      if (value === undefined) delete merged[key];
    }
    await this.redis.set(
      `booking:status:${bookingId}`,
      JSON.stringify(merged),
      24 * 60 * 60,
    );
  }

  async getCachedBookingStatus(
    bookingId: string,
  ): Promise<Record<string, any> | null> {
    const data = await this.redis.get(`booking:status:${bookingId}`);
    try {
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  }

  async cacheFcmToken(userId: string, token: string): Promise<void> {
    await this.redis.set(`user:fcm:${userId}`, token, 7 * 24 * 60 * 60);
  }

  async getCachedFcmToken(userId: string): Promise<string | null> {
    return this.redis.get(`user:fcm:${userId}`);
  }

  async addPendingBooking(workerId: string, bookingId: string): Promise<void> {
    await this.redis.zAdd(
      `worker:pending:${workerId}`,
      Date.now(),
      bookingId,
      120,
    );
  }

  async removePendingBooking(
    workerId: string,
    bookingId: string,
  ): Promise<void> {
    await this.redis.zRem(`worker:pending:${workerId}`, bookingId);
  }

  async getPendingBookingIds(workerId: string): Promise<string[]> {
    return this.redis.zRangeRev(`worker:pending:${workerId}`);
  }

  async markWorkerRejectedJob(
    customerId: string,
    skill: string,
    workerId: string,
  ): Promise<void> {
    await this.redis.sAdd(`rejected:${customerId}:${skill}`, workerId, 900);
  }

  async getRejectedWorkersForJob(
    customerId: string,
    skill: string,
  ): Promise<string[]> {
    return this.redis.sMembers(`rejected:${customerId}:${skill}`);
  }
}
