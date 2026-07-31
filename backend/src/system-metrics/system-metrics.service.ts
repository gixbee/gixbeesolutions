import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bull';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, Repository } from 'typeorm';
import type { Queue } from 'bull';
import * as os from 'os';
import { promises as fsp } from 'fs';
import { monitorEventLoopDelay, IntervalHistogram } from 'perf_hooks';
import { SystemLog } from '../system-logs/system-log.entity';
import { OutboxEvent, OutboxStatus } from '../outbox/outbox-event.entity';
import { RedisService } from '../redis/redis.service';

/** One point in the in-memory metrics ring buffer (sampled every 5 s). */
export interface MetricSample {
  /** Epoch ms. */
  t: number;
  /** This Node process's CPU %, normalized across all cores (0-100). */
  procCpu: number;
  /** Whole-machine CPU % (0-100). Inside Docker this is the container host view. */
  sysCpu: number;
  /** Process resident set size, bytes. */
  rss: number;
  /** V8 heap used / total, bytes. */
  heapUsed: number;
  heapTotal: number;
  /** System memory used / total, bytes. */
  sysMemUsed: number;
  sysMemTotal: number;
  /** Mean event-loop delay over the sample window, ms (spike = blocked loop). */
  loopLagMs: number;
  /** Disk free bytes (null if unreadable in this environment). */
  diskFree: number | null;
  /** Disk total bytes. */
  diskTotal: number | null;
  /** Free disk as 0-100 %. */
  diskFreePct: number | null;
}

export interface MetricAlert {
  severity: 'warning' | 'critical';
  code: string;
  message: string;
}

export interface QueueDepth {
  waiting: number;
  active: number;
  failed: number;
  delayed: number;
}

const SAMPLE_MS = 5_000;
/** 3 h of history @ 5 s. Restarting the process clears it (live monitor, not archive). */
const MAX_SAMPLES = (3 * 60 * 60 * 1000) / SAMPLE_MS;
/** Cap points returned to the UI so charts stay light. */
const MAX_POINTS_RETURNED = 400;

const ALERT_LOOP_LAG_MS = 100;
const ALERT_SYS_MEM_PCT = 85;
const ALERT_DISK_FREE_PCT = 15;
const ALERT_5XX_PER_MIN = 5;

@Injectable()
export class SystemMetricsService implements OnModuleInit, OnModuleDestroy {
  private samples: MetricSample[] = [];
  private timer: NodeJS.Timeout | null = null;

  private lastCpuUsage = process.cpuUsage();
  private lastHrtime = process.hrtime.bigint();
  private lastOsTimes = this.readOsCpuTimes();
  private loopHistogram: IntervalHistogram | null = null;
  private lastDisk: {
    free: number | null;
    total: number | null;
    freePct: number | null;
  } = { free: null, total: null, freePct: null };
  private diskSampleCounter = 0;

  constructor(
    @InjectRepository(SystemLog)
    private readonly logsRepo: Repository<SystemLog>,
    @InjectRepository(OutboxEvent)
    private readonly outboxRepo: Repository<OutboxEvent>,
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
    @InjectQueue('bookings') private readonly bookingsQueue: Queue,
    @InjectQueue('outbox') private readonly outboxQueue: Queue,
  ) {}

  onModuleInit() {
    this.loopHistogram = monitorEventLoopDelay({ resolution: 20 });
    this.loopHistogram.enable();
    void this.refreshDisk().then(() => this.sample());
  }

  onModuleDestroy() {
    this.loopHistogram?.disable();
  }

  // ── Sampling ─────────────────────────────────────────────────────────────

  private readOsCpuTimes() {
    let idle = 0;
    let total = 0;
    for (const cpu of os.cpus()) {
      idle += cpu.times.idle;
      total +=
        cpu.times.user +
        cpu.times.nice +
        cpu.times.sys +
        cpu.times.idle +
        cpu.times.irq;
    }
    return { idle, total };
  }

  /**
   * Disk free/total via fs.statfs (Node 18.15+). Inside Docker this is the
   * container filesystem view — enough to catch a filling volume.
   * Refreshed every ~30 s so sampling stays cheap.
   */
  private async refreshDisk(): Promise<void> {
    try {
      const statfs = (
        fsp as typeof fsp & {
          statfs?: (path: string) => Promise<{
            bsize: number | bigint;
            blocks: number | bigint;
            bavail: number | bigint;
            bfree: number | bigint;
          }>;
        }
      ).statfs;
      if (typeof statfs !== 'function') {
        this.lastDisk = { free: null, total: null, freePct: null };
        return;
      }
      const s = await statfs('/');
      const bsize = Number(s.bsize);
      const total = Number(s.blocks) * bsize;
      const free = Number(s.bavail ?? s.bfree) * bsize;
      this.lastDisk = {
        free,
        total,
        freePct: total > 0 ? round1((free / total) * 100) : null,
      };
    } catch {
      this.lastDisk = { free: null, total: null, freePct: null };
    }
  }

  private sample() {
    // Process CPU% — cpuUsage delta over wall-clock delta, / core count.
    const nowHr = process.hrtime.bigint();
    const cpu = process.cpuUsage();
    const elapsedUs = Number(nowHr - this.lastHrtime) / 1_000;
    const usedUs =
      cpu.user -
      this.lastCpuUsage.user +
      (cpu.system - this.lastCpuUsage.system);
    const cores = os.cpus().length || 1;
    const procCpu =
      elapsedUs > 0 ? Math.min(100, (usedUs / elapsedUs) * (100 / cores)) : 0;
    this.lastCpuUsage = cpu;
    this.lastHrtime = nowHr;

    // System CPU% — os tick deltas.
    const osTimes = this.readOsCpuTimes();
    const dIdle = osTimes.idle - this.lastOsTimes.idle;
    const dTotal = osTimes.total - this.lastOsTimes.total;
    const sysCpu = dTotal > 0 ? Math.min(100, 100 * (1 - dIdle / dTotal)) : 0;
    this.lastOsTimes = osTimes;

    // Memory.
    const mem = process.memoryUsage();
    const sysMemTotal = os.totalmem();
    const sysMemUsed = sysMemTotal - os.freemem();

    // Event-loop lag (ns → ms), reset per window.
    const loopLagMs = this.loopHistogram
      ? this.loopHistogram.mean / 1_000_000
      : 0;
    this.loopHistogram?.reset();

    // Disk every ~6 samples (~30 s).
    this.diskSampleCounter += 1;
    if (this.diskSampleCounter % 6 === 0) {
      void this.refreshDisk();
    }

    this.samples.push({
      t: Date.now(),
      procCpu: round1(procCpu),
      sysCpu: round1(sysCpu),
      rss: mem.rss,
      heapUsed: mem.heapUsed,
      heapTotal: mem.heapTotal,
      sysMemUsed,
      sysMemTotal,
      loopLagMs: round1(loopLagMs),
      diskFree: this.lastDisk.free,
      diskTotal: this.lastDisk.total,
      diskFreePct: this.lastDisk.freePct,
    });
    if (this.samples.length > MAX_SAMPLES) {
      this.samples.splice(0, this.samples.length - MAX_SAMPLES);
    }
  }

  // ── Health / outbox / queues ─────────────────────────────────────────────

  private async pingPostgres(): Promise<boolean> {
    try {
      await this.dataSource.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  private async queueDepth(queue: Queue): Promise<QueueDepth> {
    try {
      const [waiting, active, failed, delayed] = await Promise.all([
        queue.getWaitingCount(),
        queue.getActiveCount(),
        queue.getFailedCount(),
        queue.getDelayedCount(),
      ]);
      return { waiting, active, failed, delayed };
    } catch {
      return { waiting: -1, active: -1, failed: -1, delayed: -1 };
    }
  }

  private async outboxCounts(): Promise<{ pending: number; failed: number }> {
    try {
      const rows: { status: string; count: string }[] = await this.outboxRepo
        .createQueryBuilder('o')
        .select('o.status', 'status')
        .addSelect('COUNT(*)', 'count')
        .where('o.status IN (:...st)', {
          st: [OutboxStatus.PENDING, OutboxStatus.FAILED],
        })
        .groupBy('o.status')
        .getRawMany();
      let pending = 0;
      let failed = 0;
      for (const r of rows) {
        const n = Number(r.count);
        if (r.status === OutboxStatus.PENDING) pending = n;
        if (r.status === OutboxStatus.FAILED) failed = n;
      }
      return { pending, failed };
    } catch {
      return { pending: -1, failed: -1 };
    }
  }

  private async errorsLastMinute(): Promise<number> {
    try {
      const since = new Date(Date.now() - 60_000);
      return await this.logsRepo
        .createQueryBuilder('log')
        .where('log.createdAt >= :since', { since })
        .andWhere('log.level = :lvl', { lvl: 'ERROR' })
        .getCount();
    } catch {
      return 0;
    }
  }

  private buildAlerts(input: {
    latest: MetricSample | null;
    postgresUp: boolean;
    redisUp: boolean;
    outboxFailed: number;
    errors1m: number;
  }): MetricAlert[] {
    const alerts: MetricAlert[] = [];
    const { latest } = input;

    if (!input.postgresUp) {
      alerts.push({
        severity: 'critical',
        code: 'postgres_down',
        message: 'Postgres ping failed (SELECT 1)',
      });
    }
    if (!input.redisUp) {
      alerts.push({
        severity: 'critical',
        code: 'redis_down',
        message: 'Redis is not ready / ping failed',
      });
    }
    if (latest && latest.loopLagMs > ALERT_LOOP_LAG_MS) {
      alerts.push({
        severity: 'warning',
        code: 'event_loop_lag',
        message: `Event-loop lag ${latest.loopLagMs} ms (threshold ${ALERT_LOOP_LAG_MS} ms)`,
      });
    }
    if (latest && latest.sysMemTotal > 0) {
      const pct = (latest.sysMemUsed / latest.sysMemTotal) * 100;
      if (pct > ALERT_SYS_MEM_PCT) {
        alerts.push({
          severity: 'warning',
          code: 'sys_mem_high',
          message: `System memory ${Math.round(pct)}% used (threshold ${ALERT_SYS_MEM_PCT}%)`,
        });
      }
    }
    if (
      latest?.diskFreePct != null &&
      latest.diskFreePct < ALERT_DISK_FREE_PCT
    ) {
      alerts.push({
        severity: 'critical',
        code: 'disk_low',
        message: `Disk free ${latest.diskFreePct}% (threshold ${ALERT_DISK_FREE_PCT}%)`,
      });
    }
    if (input.errors1m >= ALERT_5XX_PER_MIN) {
      alerts.push({
        severity: 'critical',
        code: 'error_spike',
        message: `${input.errors1m} ERROR logs in the last minute (threshold ${ALERT_5XX_PER_MIN})`,
      });
    }
    if (input.outboxFailed > 0) {
      alerts.push({
        severity: 'critical',
        code: 'outbox_failed',
        message: `${input.outboxFailed} outbox event(s) in FAILED state`,
      });
    }
    return alerts;
  }

  // ── Read API ─────────────────────────────────────────────────────────────

  /** Latest snapshot + host/process info + health / queues / alerts. */
  async current() {
    this.sample();
    const latest = this.samples[this.samples.length - 1] ?? null;

    const [
      postgresUp,
      redisUp,
      redisStats,
      outbox,
      bookingsQ,
      outboxQ,
      errors1m,
    ] = await Promise.all([
      this.pingPostgres(),
      this.redis.ping(),
      this.redis.getCacheStats(),
      this.outboxCounts(),
      this.queueDepth(this.bookingsQueue),
      this.queueDepth(this.outboxQueue),
      this.errorsLastMinute(),
    ]);

    const alerts = this.buildAlerts({
      latest,
      postgresUp,
      redisUp,
      outboxFailed: outbox.failed,
      errors1m,
    });

    // Redis cache-health alerts. evicted_keys must stay 0 under noeviction —
    // a rising value means the eviction policy was changed and Bull jobs can
    // silently vanish. Memory nearing the cap under noeviction means cache
    // WRITES will start failing (reads keep working) — split instances then.
    if (redisStats) {
      if (redisStats.evictedKeys > 0) {
        alerts.push({
          severity: 'critical',
          code: 'redis_evictions',
          message: `Redis evicted ${redisStats.evictedKeys} key(s) — eviction policy is not noeviction; Bull jobs at risk`,
        });
      }
      if (redisStats.usedMemoryPct !== null && redisStats.usedMemoryPct > 80) {
        alerts.push({
          severity: 'warning',
          code: 'redis_mem_high',
          message: `Redis memory ${redisStats.usedMemoryPct}% of maxmemory — plan a cache/queue instance split`,
        });
      }
    }

    return {
      latest,
      meta: {
        node: process.version,
        pid: process.pid,
        platform: `${os.platform()} ${os.arch()}`,
        cores: os.cpus().length,
        hostname: os.hostname(),
        uptimeSec: Math.round(process.uptime()),
        osUptimeSec: Math.round(os.uptime()),
        loadAvg: os.loadavg().map(round1), // [1m, 5m, 15m]
        env: process.env.NODE_ENV ?? 'development',
        sampleIntervalMs: SAMPLE_MS,
        historyDepthMin: Math.round((MAX_SAMPLES * SAMPLE_MS) / 60_000),
      },
      health: {
        postgres: postgresUp,
        redis: redisUp,
      },
      /** Cache effectiveness — hitRatio, memory vs cap, evictions, ops/sec. */
      redisStats,
      outbox,
      queues: {
        bookings: bookingsQ,
        outbox: outboxQ,
      },
      traffic1m: {
        errors: errors1m,
      },
      alerts,
    };
  }

  /** Ring-buffer slice for the last `minutes`, downsampled to ≤400 points. */
  history(minutes: number) {
    const cutoff = Date.now() - minutes * 60_000;
    let pts = this.samples.filter((s) => s.t >= cutoff);
    if (pts.length > MAX_POINTS_RETURNED) {
      const stride = Math.ceil(pts.length / MAX_POINTS_RETURNED);
      pts = pts.filter((_, i) => i % stride === 0);
    }
    return { minutes, points: pts };
  }

  /**
   * Per-minute traffic derived from system_logs: request count, error count
   * (5xx), warn count (4xx), and average duration — the "spikes" view.
   */
  async traffic(minutes: number) {
    const since = new Date(Date.now() - minutes * 60_000);
    const rows: {
      minute: Date;
      total: string;
      errors: string;
      warns: string;
      avgms: string | null;
    }[] = await this.logsRepo
      .createQueryBuilder('log')
      .select(`date_trunc('minute', log.createdAt)`, 'minute')
      .addSelect('COUNT(*)', 'total')
      .addSelect(`COUNT(*) FILTER (WHERE log.level = 'ERROR')`, 'errors')
      .addSelect(`COUNT(*) FILTER (WHERE log.level = 'WARN')`, 'warns')
      .addSelect('AVG(log.durationMs)', 'avgms')
      .where('log.createdAt >= :since', { since })
      .groupBy('minute')
      .orderBy('minute', 'ASC')
      .getRawMany();

    return {
      minutes,
      points: rows.map((r) => ({
        t: new Date(r.minute).getTime(),
        total: Number(r.total),
        errors: Number(r.errors),
        warns: Number(r.warns),
        avgMs: r.avgms == null ? null : Math.round(Number(r.avgms)),
      })),
    };
  }
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
