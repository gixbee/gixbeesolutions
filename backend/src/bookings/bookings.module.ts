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

@Module({
  imports: [
    TypeOrmModule.forFeature([Booking, WorkerProfile]),
    BullModule.registerQueue({
      name: 'bookings',
    }),
    WalletsModule,
    NotificationsModule,
    WorkersModule,
  ],
  controllers: [BookingsController],
  providers: [BookingsService, BookingsProcessor],
  exports: [BookingsService],
})
export class BookingsModule {}
