import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkerProfile } from './worker-profile.entity';
import {
  WorkerStrike,
  WorkerStrikeStatus,
  WorkerStrikeType,
} from './worker-strike.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import {
  SUSPENSION_STRIKE_THRESHOLD,
  WORKERS_LIST_CACHE_KEY,
} from './worker.shared';

@Injectable()
export class WorkerStrikeService {
  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(WorkerStrike)
    private readonly strikesRepository: Repository<WorkerStrike>,
    private readonly redisService: RedisService,
    private readonly notificationsService: NotificationsService,
  ) {}

  /** @deprecated kept for old callers — use recordStrike with a real reason. */
  async addStrike(userId: string): Promise<void> {
    await this.recordStrike(userId, {
      type: WorkerStrikeType.ADMIN,
      reason: 'Policy violation recorded by the system.',
    });
  }

  /**
   * Record a strike against a worker WITH a written reason, notify them, and
   * suspend (block Go Live + pull from dispatch) at the threshold.
   */
  async recordStrike(
    userId: string,
    opts: { type: WorkerStrikeType; reason: string; bookingId?: string },
  ): Promise<{ strikeCount: number; suspended: boolean }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
      relations: ['user'],
    });
    if (!profile) return { strikeCount: 0, suspended: false };

    await this.strikesRepository.save(
      this.strikesRepository.create({
        workerUserId: userId,
        bookingId: opts.bookingId ?? null,
        type: opts.type,
        reason: opts.reason,
        status: WorkerStrikeStatus.ACTIVE,
      }),
    );

    profile.strikeCount = (profile.strikeCount || 0) + 1;
    const suspended = profile.strikeCount >= SUSPENSION_STRIKE_THRESHOLD;
    if (suspended) profile.isActive = false;
    await this.workersRepository.save(profile);

    if (suspended) {
      // Fully remove from dispatch — the old code left suspended workers in
      // the Redis geo/skill index, so they kept receiving job pings.
      await this.redisService.del(`worker:location:${userId}`).catch(() => {});
      await this.redisService.del(`worker:status:${userId}`).catch(() => {});
      await this.redisService.del(`worker:snapshot:${userId}`).catch(() => {});
      await this.redisService
        .unindexWorkerSkills(userId, profile.skills || [])
        .catch(() => {});
      await this.redisService.removeWorkerFromGeoIndex(userId).catch(() => {});
      await this.redisService.del(WORKERS_LIST_CACHE_KEY).catch(() => {});
    }

    // Written notice — the worker must always know WHY and what to do next.
    await this.notificationsService
      .sendToUser(userId, {
        title: suspended
          ? 'Account suspended — you can appeal'
          : `Strike ${profile.strikeCount} of ${SUSPENSION_STRIKE_THRESHOLD}`,
        body: suspended
          ? `${opts.reason} You now have ${profile.strikeCount} strikes and cannot go live. Open Profile → Strikes to appeal — our team reviews every appeal.`
          : `${opts.reason} At ${SUSPENSION_STRIKE_THRESHOLD} strikes you will be suspended. You can view or appeal this in Profile → Strikes.`,
        data: {
          type: 'worker_strike',
          strikeCount: String(profile.strikeCount),
          suspended: String(suspended),
        },
      })
      .catch((e) =>
        console.error('[RecordStrike] notification failed:', e?.message ?? e),
      );

    return { strikeCount: profile.strikeCount, suspended };
  }

  /** The worker's own strike history — Profile → Strikes screen. */
  async getMyStrikes(userId: string): Promise<{
    strikeCount: number;
    suspended: boolean;
    threshold: number;
    strikes: WorkerStrike[];
  }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    const strikes = await this.strikesRepository.find({
      where: { workerUserId: userId },
      order: { createdAt: 'DESC' },
      take: 50,
    });
    const count = profile?.strikeCount || 0;
    return {
      strikeCount: count,
      suspended: count >= SUSPENSION_STRIKE_THRESHOLD,
      threshold: SUSPENSION_STRIKE_THRESHOLD,
      strikes,
    };
  }

  /** Worker files an appeal on one of their own ACTIVE strikes. */
  async appealStrike(
    userId: string,
    strikeId: string,
    message: string,
  ): Promise<{ message: string }> {
    const strike = await this.strikesRepository.findOne({
      where: { id: strikeId, workerUserId: userId },
    });
    if (!strike) throw new NotFoundException('Strike not found');
    if (strike.status === WorkerStrikeStatus.OVERTURNED) {
      throw new BadRequestException('This strike was already overturned.');
    }
    if (strike.status !== WorkerStrikeStatus.ACTIVE) {
      throw new BadRequestException(
        'This strike was already appealed and reviewed.',
      );
    }
    strike.status = WorkerStrikeStatus.APPEALED;
    strike.appealMessage = message;
    strike.appealedAt = new Date();
    await this.strikesRepository.save(strike);
    return {
      message:
        'Appeal submitted. Our team will review it and you will be notified of the outcome.',
    };
  }

  /** Admin: strike queue (default = appeals awaiting review). */
  async adminListStrikes(status?: string): Promise<WorkerStrike[]> {
    const where: any = {};
    if (status) where.status = status as WorkerStrikeStatus;
    return this.strikesRepository.find({
      where,
      order: { appealedAt: 'DESC', createdAt: 'DESC' },
      take: 200,
    });
  }

  /**
   * Admin resolves an appealed strike. Overturning decrements the profile
   * count — dropping below the threshold lifts the Go Live suspension
   * immediately (the worker still has to toggle Go Live themselves).
   */
  async adminResolveStrike(
    strikeId: string,
    overturn: boolean,
    note?: string,
  ): Promise<WorkerStrike> {
    const strike = await this.strikesRepository.findOne({
      where: { id: strikeId },
    });
    if (!strike) throw new NotFoundException('Strike not found');
    if (
      strike.status === WorkerStrikeStatus.OVERTURNED ||
      strike.status === WorkerStrikeStatus.UPHELD
    ) {
      throw new BadRequestException('This strike is already resolved.');
    }

    strike.status = overturn
      ? WorkerStrikeStatus.OVERTURNED
      : WorkerStrikeStatus.UPHELD;
    strike.resolutionNote = note ?? null;
    strike.resolvedAt = new Date();
    await this.strikesRepository.save(strike);

    if (overturn) {
      const profile = await this.workersRepository.findOne({
        where: { user: { id: strike.workerUserId } },
      });
      if (profile) {
        profile.strikeCount = Math.max(0, (profile.strikeCount || 0) - 1);
        await this.workersRepository.save(profile);
      }
    }

    await this.notificationsService
      .sendToUser(strike.workerUserId, {
        title: overturn
          ? 'Appeal accepted — strike removed'
          : 'Appeal reviewed',
        body: overturn
          ? `Your appeal was accepted and the strike no longer counts.${note ? ' Note: ' + note : ''} If you were suspended, you can go live again.`
          : `Your appeal was reviewed and the strike stands.${note ? ' Note: ' + note : ''}`,
        data: {
          type: 'strike_resolved',
          strikeId,
          overturned: String(overturn),
        },
      })
      .catch(() => {});

    return strike;
  }

}
