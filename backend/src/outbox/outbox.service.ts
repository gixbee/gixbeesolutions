import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { EntityManager, LessThan, Repository } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { OutboxEvent, OutboxStatus } from './outbox-event.entity';

const MAX_ATTEMPTS = 10;

@Injectable()
export class OutboxService {
  private readonly logger = new Logger(OutboxService.name);

  constructor(
    @InjectRepository(OutboxEvent)
    private readonly outboxRepo: Repository<OutboxEvent>,
    @InjectQueue('outbox') private readonly outboxQueue: Queue,
  ) {}

  /**
   * Persist an outbox row using the caller's transaction manager.
   * MUST be called inside the same transaction as the booking mutation.
   */
  async append(
    manager: EntityManager,
    type: string,
    aggregateId: string,
    payload: Record<string, unknown>,
  ): Promise<OutboxEvent> {
    const row = manager.create(OutboxEvent, {
      type,
      aggregateId,
      payload,
      status: OutboxStatus.PENDING,
      attempts: 0,
      processedAt: null,
      lastError: null,
    });
    return manager.save(row);
  }

  /** Best-effort low-latency kick after commit (poller is the safety net). */
  async enqueueDispatch(eventId: string): Promise<void> {
    try {
      await this.outboxQueue.add(
        'dispatch',
        { eventId },
        {
          jobId: `outbox-dispatch:${eventId}`,
          attempts: 5,
          backoff: { type: 'exponential', delay: 2000 },
          removeOnComplete: true,
          removeOnFail: 50,
        },
      );
    } catch (e) {
      // Duplicate jobId is fine (idempotent kick). Other errors: poller retries.
      this.logger.warn(
        `enqueueDispatch(${eventId}) failed (poller will retry): ${
          (e as Error)?.message ?? e
        }`,
      );
    }
  }

  async findById(id: string): Promise<OutboxEvent | null> {
    return this.outboxRepo.findOne({ where: { id } });
  }

  /** Oldest pending events still under the attempt budget (poller safety net). */
  async findDispatchable(limit = 25): Promise<OutboxEvent[]> {
    return this.outboxRepo.find({
      where: {
        status: OutboxStatus.PENDING,
        attempts: LessThan(MAX_ATTEMPTS),
      },
      order: { createdAt: 'ASC' },
      take: limit,
    });
  }

  /**
   * Atomically claim an event for processing — compare-and-set on `attempts`.
   * With multiple replicas (or the 'dispatch' kick racing the 'poll' tick),
   * only ONE worker's UPDATE matches; everyone else sees affected=0 and
   * skips, preventing duplicate FCM pushes / handler side effects.
   * The claim itself counts as the attempt: if the process crashes
   * mid-handle, the row stays PENDING with the attempt recorded, and the
   * poller retries it on a later tick.
   */
  async claim(id: string, expectedAttempts: number): Promise<boolean> {
    const res = await this.outboxRepo
      .createQueryBuilder()
      .update(OutboxEvent)
      .set({ attempts: () => '"attempts" + 1' })
      .where('id = :id', { id })
      .andWhere('status = :pending', { pending: OutboxStatus.PENDING })
      .andWhere('attempts = :expectedAttempts', { expectedAttempts })
      .execute();
    return (res.affected ?? 0) === 1;
  }

  /**
   * Record a failure for an event that was already claimed (attempts was
   * incremented by `claim`, so this only sets the error / terminal status).
   */
  async recordFailureAfterClaim(id: string, errorMessage: string): Promise<void> {
    const row = await this.outboxRepo.findOne({ where: { id } });
    if (!row) return;
    const attempts = row.attempts ?? 0;
    const status =
      attempts >= MAX_ATTEMPTS ? OutboxStatus.FAILED : OutboxStatus.PENDING;
    await this.outboxRepo.update(id, {
      status,
      lastError: errorMessage.slice(0, 2000),
      processedAt: status === OutboxStatus.FAILED ? new Date() : null,
    });
    if (status === OutboxStatus.FAILED) {
      this.logger.error(
        `Outbox event ${id} marked FAILED after ${attempts} attempts: ${errorMessage}`,
      );
    }
  }

  async markProcessed(id: string): Promise<void> {
    await this.outboxRepo.update(id, {
      status: OutboxStatus.PROCESSED,
      processedAt: new Date(),
      lastError: null,
    });
  }

  async recordAttempt(id: string, errorMessage: string): Promise<void> {
    const row = await this.outboxRepo.findOne({ where: { id } });
    if (!row) return;
    const attempts = (row.attempts ?? 0) + 1;
    const status =
      attempts >= MAX_ATTEMPTS ? OutboxStatus.FAILED : OutboxStatus.PENDING;
    await this.outboxRepo.update(id, {
      attempts,
      status,
      lastError: errorMessage.slice(0, 2000),
      processedAt: status === OutboxStatus.FAILED ? new Date() : null,
    });
    if (status === OutboxStatus.FAILED) {
      this.logger.error(
        `Outbox event ${id} marked FAILED after ${attempts} attempts: ${errorMessage}`,
      );
    }
  }

  get maxAttempts(): number {
    return MAX_ATTEMPTS;
  }
}
