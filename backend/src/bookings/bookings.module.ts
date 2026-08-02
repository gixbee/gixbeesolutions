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
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { BookingStatusService } from './booking-status.service';
import { BookingCancelService } from './booking-cancel.service';
import { BookingDispatchService } from './booking-dispatch.service';
import { BookingSettlementService } from './booking-settlement.service';
import { BookingProgressService } from './booking-progress.service';
import { BookingClaimService } from './booking-claim.service';
import { BookingBroadcastService } from './booking-broadcast.service';

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
    MasterEntriesModule,
  ],
  controllers: [BookingsController],
  providers: [
    BookingsService,
    BookingsProcessor,
    BookingStatusService,
    BookingCancelService,
    BookingClaimService,
    BookingBroadcastService,
    BookingDispatchService,
    BookingSettlementService,
    BookingProgressService,
  ],
  exports: [BookingsService],
})
export class BookingsModule {}
