import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { PaymentOrder } from './payment-order.entity';
import { WalletsModule } from '../wallets/wallets.module';
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { WorkersModule } from '../workers/workers.module';
import { BookingsModule } from '../bookings/bookings.module';
import { HiringModule } from '../hiring/hiring.module';
import { BillingModule } from '../billing/billing.module';

@Module({
  imports: [
    BillingModule,
    TypeOrmModule.forFeature([PaymentOrder]),
    WalletsModule,
    MasterEntriesModule,
    WorkersModule,
    BookingsModule,
    forwardRef(() => HiringModule),
  ],
  providers: [PaymentsService],
  controllers: [PaymentsController],
  exports: [PaymentsService],
})
export class PaymentsModule {}
