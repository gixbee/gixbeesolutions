import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bull';
import { Booking } from './booking.entity';
import { BookingsController } from './bookings.controller';
import { BookingsService } from './bookings.service';
import { BookingsProcessor } from './bookings.processor';
import { WalletsModule } from '../wallets/wallets.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { WorkersModule } from '../workers/workers.module';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { MessagesModule } from '../messages/messages.module';
import { OutboxModule } from '../outbox/outbox.module';
import { SystemLogsModule } from '../system-logs/system-logs.module';
import { BillingModule } from '../billing/billing.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Booking, WorkerProfile]),
    BullModule.registerQueue({
      name: 'bookings',
    }),
    WalletsModule,
    NotificationsModule,
    WorkersModule,
    MessagesModule,
    OutboxModule,
    SystemLogsModule,
    BillingModule,
  ],
  controllers: [BookingsController],
  providers: [BookingsService, BookingsProcessor],
  exports: [BookingsService],
})
export class BookingsModule {}
