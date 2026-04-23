import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { JobPost } from './job-post.entity';
import { JobApplication } from './job-application.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { HiringService } from './hiring.service';
import { HiringController } from './hiring.controller';
import { NotificationsModule } from '../notifications/notifications.module';
import { TalentModule } from '../talent/talent.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([JobPost, JobApplication, WorkerProfile]),
    NotificationsModule,
    TalentModule,
  ],
  controllers: [HiringController],
  providers: [HiringService],
  exports: [HiringService],
})
export class HiringModule {}
