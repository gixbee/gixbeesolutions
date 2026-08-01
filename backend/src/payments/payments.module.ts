import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { PaymentOrder } from './payment-order.entity';
import { WalletsModule } from '../wallets/wallets.module';
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { WorkersModule } from '../workers/workers.module';
import { BookingsModule } from '../bookings/bookings.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([PaymentOrder]),
    WalletsModule,
    MasterEntriesModule,
    WorkersModule,
    BookingsModule,
  ],
  providers: [PaymentsService],
  controllers: [PaymentsController],
  exports: [PaymentsService],
})
export class PaymentsModule {}
