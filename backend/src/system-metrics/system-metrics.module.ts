import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bull';
import { SystemLog } from '../system-logs/system-log.entity';
import { OutboxEvent } from '../outbox/outbox-event.entity';
import { SystemMetricsService } from './system-metrics.service';
import { SystemMetricsController } from './system-metrics.controller';

/**
 * Live CPU / memory / event-loop / traffic metrics for the admin portal.
 * Metrics live in an in-memory ring buffer (3 h @ 5 s); traffic charts are
 * computed from the system_logs table. Health/outbox/queue depths are
 * queried on each /admin/current poll.
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([SystemLog, OutboxEvent]),
    BullModule.registerQueue({ name: 'bookings' }),
    BullModule.registerQueue({ name: 'outbox' }),
  ],
  providers: [SystemMetricsService],
  controllers: [SystemMetricsController],
  exports: [SystemMetricsService],
})
export class SystemMetricsModule {}
