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
      await this.outboxQueue.add(
        'poll',
        {},
        {
          jobId: 'outbox-poll-repeat',
          repeat: { every: 5000 },
          removeOnComplete: true,
          removeOnFail: true,
        },
      );
      this.logger.log('Outbox poller registered (every 5s)');
    } catch (e) {
      this.logger.warn(
        `Outbox poller registration skipped: ${(e as Error)?.message ?? e}`,
      );
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
