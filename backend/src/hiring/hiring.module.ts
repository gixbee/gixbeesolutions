import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bull';
import { JobPost } from './job-post.entity';
import { JobApplication } from './job-application.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { HiringService } from './hiring.service';
import { HiringController } from './hiring.controller';
import { NotificationsModule } from '../notifications/notifications.module';
import { TalentModule } from '../talent/talent.module';
import { WalletsModule } from '../wallets/wallets.module';
import { JobPreference } from './matching/job-preference.entity';
import { HiringRequest } from './matching/hiring-request.entity';
import { HiringInterest } from './matching/hiring-interest.entity';
import { MatchingService } from './matching/matching.service';
import { MatchingController } from './matching/matching.controller';
import { HiringMatchProcessor } from './matching/hiring-match.processor';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      JobPost,
      JobApplication,
      WorkerProfile,
      // Smart Hiring (FRD: Find a Job + Hire Employee matching engine)
      JobPreference,
      HiringRequest,
      HiringInterest,
    ]),
    BullModule.registerQueue({ name: 'hiring' }),
    NotificationsModule,
    TalentModule,
    WalletsModule,
  ],
  controllers: [HiringController, MatchingController],
  providers: [HiringService, MatchingService, HiringMatchProcessor],
  exports: [HiringService, MatchingService],
})
export class HiringModule {}
