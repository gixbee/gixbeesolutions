import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WalletsModule } from '../wallets/wallets.module';
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { WorkersController } from './workers.controller';
import { WorkersService } from './workers.service';
import { WorkerAvailabilityService } from './worker-availability.service';
import { WorkerGoLiveService } from './worker-golive.service';
import { WorkerStrikeService } from './worker-strike.service';
import { WorkerProfile } from './worker-profile.entity';
import { WorkerStrike } from './worker-strike.entity';
import { Booking } from '../bookings/booking.entity';
import { User } from '../users/user.entity';

import { JobCredit } from '../billing/job-credit.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      WorkerProfile,
      WorkerStrike,
      TalentProfile,
      ProfessionalSkill,
      Booking,
      User,
      JobCredit,
    ]),
    WalletsModule,
    // Go-Live limits (daily cap, wallet floor) are admin-editable CONFIGURATION
    // master entries — see MasterEntriesService.getConfigNumber.
    MasterEntriesModule,
    // Strike notices + appeal outcomes are pushed to the worker via FCM.
    NotificationsModule,
  ],
  controllers: [WorkersController],
  providers: [
    WorkersService,
    WorkerAvailabilityService,
    WorkerGoLiveService,
    WorkerStrikeService,
  ],
  exports: [WorkersService],
})
export class WorkersModule {}
