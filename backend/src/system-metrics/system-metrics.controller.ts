import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { SystemMetricsService } from './system-metrics.service';

/** Clamp helper: default + bounds for the ?minutes= query. */
const clampMinutes = (raw: string | undefined, def: number, max: number) => {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return def;
  return Math.min(max, Math.max(1, Math.floor(n)));
};

/**
 * Live server metrics for the admin portal's Monitoring page.
 * ADMIN-only — exposes host details (hostname, memory, load).
 * Page ACL: operators need the `monitoring` portal page.
 */
@Controller('system-metrics')
@UseGuards(JwtAuthGuard, AdminGuard)
@RequireAdminPage('monitoring')
export class SystemMetricsController {
  constructor(private readonly service: SystemMetricsService) {}

  /** Latest sample + host/process meta + health / outbox / queues / alerts. */
  @Get('admin/current')
  current() {
    return this.service.current();
  }

  /** CPU/memory/event-loop time series (in-memory ring buffer, ≤3 h). */
  @Get('admin/history')
  history(@Query('minutes') minutes?: string) {
    return this.service.history(clampMinutes(minutes, 30, 180));
  }

  /** Requests/errors per minute + avg latency, from system_logs. */
  @Get('admin/traffic')
  traffic(@Query('minutes') minutes?: string) {
    return this.service.traffic(clampMinutes(minutes, 60, 24 * 60));
  }
}
