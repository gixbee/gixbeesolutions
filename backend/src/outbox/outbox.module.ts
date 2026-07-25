import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bull';
import { OutboxEvent } from './outbox-event.entity';
import { OutboxService } from './outbox.service';
import { OutboxDispatcher } from './outbox.dispatcher';
import { BookingLifecycleHandler } from './booking-lifecycle.handler';
import { NotificationsModule } from '../notifications/notifications.module';
import { WorkersModule } from '../workers/workers.module';
import { MessagesModule } from '../messages/messages.module';
import { SystemLogsModule } from '../system-logs/system-logs.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([OutboxEvent]),
    BullModule.registerQueue({ name: 'outbox' }),
    // Handler schedules requestTimeout / GPS jobs on the existing bookings queue.
    BullModule.registerQueue({ name: 'bookings' }),
    NotificationsModule,
    WorkersModule,
    MessagesModule,
    SystemLogsModule,
  ],
  providers: [OutboxService, BookingLifecycleHandler, OutboxDispatcher],
  exports: [OutboxService],
})
export class OutboxModule {}
