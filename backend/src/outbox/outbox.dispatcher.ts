import { Process, Processor } from '@nestjs/bull';
import { InjectQueue } from '@nestjs/bull';
import { Logger, OnModuleInit } from '@nestjs/common';
import type { Job, Queue } from 'bull';
import { OutboxService } from './outbox.service';
import { BookingLifecycleHandler } from './booking-lifecycle.handler';
import { OutboxStatus } from './outbox-event.entity';
import { SystemLogsService } from '../system-logs/system-logs.service';
import {
  SystemLogLevel,
  SystemLogType,
} from '../system-logs/system-log.entity';

/** Safety-net sweep interval. Part of the Bull repeatable key — see prune. */
const POLL_EVERY_MS = 5000;
/** Stable id so all replicas register the same repeatable. */
const POLL_JOB_ID = 'outbox-poll-repeat';
const POLL_JOB_NAME = 'poll';

/**
 * Dispatches pending outbox rows on a dedicated `outbox` queue:
 *  - `dispatch` — immediate kick after commit (by event id)
 *  - `poll` — repeatable every 5s safety net for missed kicks
 */
@Processor('outbox')
export class OutboxDispatcher implements OnModuleInit {
  private readonly logger = new Logger(OutboxDispatcher.name);

  constructor(
    private readonly outboxService: OutboxService,
    private readonly handler: BookingLifecycleHandler,
    private readonly systemLogs: SystemLogsService,
    @InjectQueue('outbox') private readonly outboxQueue: Queue,
  ) {}

  async onModuleInit(): Promise<void> {
    try {
      await this.pruneStaleRepeatables();
      await this.outboxQueue.add(
        POLL_JOB_NAME,
        {},
        {
          jobId: POLL_JOB_ID,
          repeat: { every: POLL_EVERY_MS },
          removeOnComplete: true,
          removeOnFail: true,
        },
      );
      this.logger.log(`Outbox poller registered (every ${POLL_EVERY_MS}ms)`);
    } catch (e) {
      this.logger.warn(
        `Outbox poller registration skipped: ${(e as Error)?.message ?? e}`,
      );
    }
  }

  /**
   * Bull derives a repeatable's identity from name + jobId + interval, so
   * every replica registering the poller with the same values collapses onto
   * one scheduler. Changing POLL_EVERY_MS or POLL_JOB_ID mints a *new*
   * identity and orphans the old one, which keeps firing forever because it
   * lives in Redis and outlives the deploy that removed it. Drop every
   * repeatable that isn't the current config before registering.
   */
  private async pruneStaleRepeatables(): Promise<void> {
    const existing = await this.outboxQueue.getRepeatableJobs();
    for (const job of existing) {
      const isCurrent =
        job.name === POLL_JOB_NAME &&
        job.id === POLL_JOB_ID &&
        Number(job.every) === POLL_EVERY_MS;
      if (isCurrent) continue;
      await this.outboxQueue.removeRepeatableByKey(job.key);
      this.logger.warn(`Removed stale outbox repeatable: ${job.key}`);
    }
  }

  @Process('dispatch')
  async handleDispatch(job: Job<{ eventId: string }>): Promise<void> {
    const { eventId } = job.data ?? {};
    if (!eventId) return;
    await this.dispatchOne(eventId);
  }

  @Process('poll')
  async handlePoll(): Promise<void> {
    const pending = await this.outboxService.findDispatchable(25);
    for (const row of pending) {
      await this.dispatchOne(row.id);
    }
  }

  /** Exposed for unit tests — claim, handle, mark processed (idempotent). */
  async dispatchOne(
    eventId: string,
  ): Promise<'processed' | 'skipped' | 'failed'> {
    const event = await this.outboxService.findById(eventId);
    if (!event) {
      this.logger.warn(`Outbox event ${eventId} not found`);
      return 'skipped';
    }
    if (event.status === OutboxStatus.PROCESSED) {
      return 'skipped';
    }
    if (
      event.status === OutboxStatus.FAILED &&
      event.attempts >= this.outboxService.maxAttempts
    ) {
      return 'skipped';
    }

    // Atomic claim: only one worker across all replicas wins this event.
    // Losers (e.g. the poll tick racing the dispatch kick) skip silently.
    const claimed = await this.outboxService.claim(eventId, event.attempts);
    if (!claimed) {
      return 'skipped';
    }

    try {
      await this.handler.handle(event);
      await this.outboxService.markProcessed(eventId);
      return 'processed';
    } catch (e) {
      const msg = (e as Error)?.message ?? String(e);
      const stack = e instanceof Error ? (e.stack ?? null) : null;
      this.logger.error(`Outbox dispatch ${eventId} failed: ${msg}`);
      await this.outboxService.recordFailureAfterClaim(eventId, msg);

      // Persist to system_logs so background failures show in the admin Logs
      // page. Successful polls intentionally do not log.
      const after = await this.outboxService.findById(eventId);
      const terminal = after?.status === OutboxStatus.FAILED;
      this.systemLogs.record({
        level: SystemLogLevel.ERROR,
        type: SystemLogType.SYSTEM,
        path: `outbox://${event.type}`,
        message: terminal
          ? `Outbox FAILED after ${after?.attempts ?? '?'} attempts: ${event.type} (${eventId.slice(0, 8)}…)`
          : `Outbox dispatch failed: ${event.type} (${eventId.slice(0, 8)}…) attempt ${after?.attempts ?? 0}`,
        detail: [
          `eventId=${eventId}`,
          `aggregateId=${event.aggregateId}`,
          `type=${event.type}`,
          `attempts=${after?.attempts ?? '?'}`,
          `status=${after?.status ?? '?'}`,
          msg,
          stack,
        ]
          .filter(Boolean)
          .join('\n'),
      });
      return 'failed';
    }
  }
}
