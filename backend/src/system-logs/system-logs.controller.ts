import { Controller, Delete, Get, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { SystemLogsService } from './system-logs.service';
import { PurgeLogsDto, QueryLogsDto } from './dto/query-logs.dto';

/**
 * Admin-portal log browser. Entire controller is ADMIN-only — logs contain
 * IPs, user ids, and stack traces, so nothing here is exposed to consumers.
 */
@Controller('system-logs')
@UseGuards(JwtAuthGuard, AdminGuard)
export class SystemLogsController {
  constructor(private readonly service: SystemLogsService) {}

  /** GET /system-logs/admin?type=DB&level=ERROR&status=5xx&search=booking&page=1 */
  @Get('admin')
  list(@Query() q: QueryLogsDto) {
    return this.service.find(q);
  }

  /** Counts for the last 24 h, powering the summary chips. */
  @Get('admin/stats')
  stats() {
    return this.service.stats();
  }

  /** DELETE /system-logs/admin/purge?olderThanDays=30 */
  @Delete('admin/purge')
  async purge(@Query() q: PurgeLogsDto) {
    const deleted = await this.service.purge(q.olderThanDays);
    return { deleted, olderThanDays: q.olderThanDays };
  }
}
