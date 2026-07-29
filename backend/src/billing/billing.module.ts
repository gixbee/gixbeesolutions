import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobCredit } from './job-credit.entity';
import { CreditTransaction } from './credit-transaction.entity';
import { JobCreditsService } from './job-credits.service';
import { JobCreditsController } from './job-credits.controller';

@Module({
  imports: [TypeOrmModule.forFeature([JobCredit, CreditTransaction])],
  providers: [JobCreditsService],
  controllers: [JobCreditsController],
  exports: [JobCreditsService],
})
export class BillingModule {}
