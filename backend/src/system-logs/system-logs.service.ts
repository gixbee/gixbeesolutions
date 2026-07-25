import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, LessThan } from 'typeorm';
import {
  SystemLog,
  SystemLogLevel,
  SystemLogType,
} from './system-log.entity';

export interface RecordLogInput {
  level?: SystemLogLevel;
  type?: SystemLogType;
  method?: string | null;
  path?: string | null;
  statusCode?: number | null;
  durationMs?: number | null;
  userId?: string | null;
  ip?: string | null;
  message?: string | null;
  detail?: string | null;
}

export interface FindLogsQuery {
  type?: SystemLogType;
  level?: SystemLogLevel;
  /** When true, restrict to WARN + ERROR (ignores `level` if both set). */
  problems?: boolean;
  /** Minimum durationMs (e.g. 1000 for slow requests). */
  minDurationMs?: number;
  method?: string;
  /** Exact status (e.g. 404) or class shorthand '4xx' / '5xx' / '2xx'. */
  status?: string;
  /** Substring match against path + message (case-insensitive). */
  search?: string;
  /** ISO date strings. */
  from?: string;
  to?: string;
  page?: number;
  limit?: number;
}

const MAX_DETAIL_CHARS = 8000;
const clip = (v: string | null | undefined, max: number): string | null =>
  v == null ? null : v.length > max ? v.slice(0, max) : v;

/** How often the auto-purge runs (once a day). */
const AUTO_PURGE_INTERVAL_MS = 24 * 60 * 60 * 1000;
/** Delay after boot before the first purge (let the app settle / table sync). */
const AUTO_PURGE_BOOT_DELAY_MS = 60 * 1000;

@Injectable()
export class SystemLogsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SystemLogsService.name);
  private purgeTimer: NodeJS.Timeout | null = null;
  private bootTimer: NodeJS.Timeout | null = null;

  /**
   * Retention window in days, from LOG_RETENTION_DAYS (default 30).
   * Set LOG_RETENTION_DAYS=0 to disable automatic purging entirely.
   */
  private readonly retentionDays: number;

  constructor(
    @InjectRepository(SystemLog)
    private readonly repo: Repository<SystemLog>,
    config: ConfigService,
  ) {
    const raw = Number(config.get<string>('LOG_RETENTION_DAYS'));
    this.retentionDays = Number.isFinite(raw) && raw >= 0 ? Math.floor(raw) : 30;
  }

  onModuleInit() {
    if (this.retentionDays <= 0) {
      this.logger.log('Auto-purge disabled (LOG_RETENTION_DAYS=0)');
      return;
    }
    this.logger.log(
      `Auto-purge enabled: system_logs older than ${this.retentionDays} days, daily`,
    );
    // First run shortly after boot, then every 24 h. unref() so the timers
    // never keep the process alive on shutdown. Purge is idempotent, so
    // multiple backend instances running it concurrently is harmless.
    this.bootTimer = setTimeout(() => this.autoPurge(), AUTO_PURGE_BOOT_DELAY_MS);
    this.bootTimer.unref?.();
    this.purgeTimer = setInterval(() => this.autoPurge(), AUTO_PURGE_INTERVAL_MS);
    this.purgeTimer.unref?.();
  }

  onModuleDestroy() {
    if (this.bootTimer) clearTimeout(this.bootTimer);
    if (this.purgeTimer) clearInterval(this.purgeTimer);
  }

  /** Scheduled retention sweep — failures logged, never thrown. */
  private async autoPurge(): Promise<void> {
    try {
      const deleted = await this.purge(this.retentionDays);
      if (deleted > 0) {
        this.logger.log(
          `Auto-purge removed ${deleted} log entries older than ${this.retentionDays} days`,
        );
      }
    } catch (err) {
      this.logger.warn(
        `Auto-purge failed: ${err instanceof Error ? err.message : err}`,
      );
    }
  }

  /**
   * Fire-and-forget insert. Logging must NEVER break or slow the request
   * path, so failures are swallowed (reported to console only) and callers
   * intentionally do not await this.
   */
  record(input: RecordLogInput): void {
    const row = this.repo.create({
      level: input.level ?? SystemLogLevel.INFO,
      type: input.type ?? SystemLogType.API,
      method: input.method ?? null,
      path: clip(input.path, 500),
      statusCode: input.statusCode ?? null,
      durationMs: input.durationMs ?? null,
      userId: clip(input.userId, 64),
      ip: clip(input.ip, 64),
      message: clip(input.message, 500),
      detail: clip(input.detail, MAX_DETAIL_CHARS),
    });
    this.repo.insert(row).catch((err) => {
      // e.g. table missing during a migration window — never rethrow.
      this.logger.warn(`Failed to persist system log: ${err?.message ?? err}`);
    });
  }

  /** Filtered, paginated listing for the admin portal. */
  async find(q: FindLogsQuery) {
    const page = Math.max(1, Number(q.page) || 1);
    const limit = Math.min(200, Math.max(1, Number(q.limit) || 50));

    const qb = this.repo.createQueryBuilder('log');

    if (q.problems) {
      qb.andWhere('log.level IN (:...levels)', {
        levels: [SystemLogLevel.WARN, SystemLogLevel.ERROR],
      });
    } else if (q.level) {
      qb.andWhere('log.level = :level', { level: q.level });
    }
    if (q.type) qb.andWhere('log.type = :type', { type: q.type });
    if (q.method) {
      qb.andWhere('log.method = :method', { method: q.method.toUpperCase() });
    }

    if (q.minDurationMs != null && Number.isFinite(q.minDurationMs)) {
      qb.andWhere('log.durationMs >= :minDur', {
        minDur: Math.max(0, Math.floor(Number(q.minDurationMs))),
      });
    }

    if (q.status) {
      const m = /^([1-5])xx$/i.exec(q.status.trim());
      if (m) {
        const base = Number(m[1]) * 100;
        qb.andWhere('log.statusCode >= :s0 AND log.statusCode < :s1', {
          s0: base,
          s1: base + 100,
        });
      } else if (/^\d{3}$/.test(q.status.trim())) {
        qb.andWhere('log.statusCode = :sc', { sc: Number(q.status.trim()) });
      }
    }

    if (q.search?.trim()) {
      qb.andWhere('(log.path ILIKE :s OR log.message ILIKE :s)', {
        s: `%${q.search.trim()}%`,
      });
    }

    if (q.from) qb.andWhere('log.createdAt >= :from', { from: new Date(q.from) });
    if (q.to) qb.andWhere('log.createdAt <= :to', { to: new Date(q.to) });

    qb.orderBy('log.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    const [data, total] = await qb.getManyAndCount();
    return { data, total, page, limit, pages: Math.ceil(total / limit) };
  }

  /** Aggregate counts for the filter chips (last 24 h). */
  async stats() {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const rows: { type: string; level: string; count: string }[] = await this.repo
      .createQueryBuilder('log')
      .select('log.type', 'type')
      .addSelect('log.level', 'level')
      .addSelect('COUNT(*)', 'count')
      .where('log.createdAt >= :since', { since })
      .groupBy('log.type')
      .addGroupBy('log.level')
      .getRawMany();

    const byType: Record<string, number> = {};
    const byLevel: Record<string, number> = {};
    let total = 0;
    for (const r of rows) {
      const n = Number(r.count);
      byType[r.type] = (byType[r.type] ?? 0) + n;
      byLevel[r.level] = (byLevel[r.level] ?? 0) + n;
      total += n;
    }
    return { since, total, byType, byLevel };
  }

  /** Delete entries older than `days` (retention). Returns rows removed. */
  async purge(days: number): Promise<number> {
    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const res = await this.repo.delete({ createdAt: LessThan(cutoff) });
    return res.affected ?? 0;
  }
}
