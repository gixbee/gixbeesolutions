import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobCredit } from './job-credit.entity';
import { CreditTransaction } from './credit-transaction.entity';
import { JobCreditsService } from './job-credits.service';
import { JobCreditsController } from './job-credits.controller';
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { JobPackPaymentsService } from './job-pack-payments.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([JobCredit, CreditTransaction]),
    MasterEntriesModule,
  ],
  providers: [JobCreditsService, JobPackPaymentsService],
  controllers: [JobCreditsController],
  exports: [JobCreditsService, JobPackPaymentsService],
})
export class BillingModule {}
