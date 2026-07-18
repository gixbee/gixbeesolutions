import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WalletsModule } from '../wallets/wallets.module';
import { MasterEntriesModule } from '../master-entries/master-entries.module';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { WorkersController } from './workers.controller';
import { WorkersService } from './workers.service';
import { WorkerProfile } from './worker-profile.entity';
import { Booking } from '../bookings/booking.entity';
import { User } from '../users/user.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([WorkerProfile, TalentProfile, ProfessionalSkill, Booking, User]),
    WalletsModule,
    // Go-Live limits (daily cap, wallet floor) are admin-editable CONFIGURATION
    // master entries — see MasterEntriesService.getConfigNumber.
    MasterEntriesModule,
  ],
  controllers: [WorkersController],
  providers: [WorkersService],
  exports: [WorkersService],
})
export class WorkersModule {}
