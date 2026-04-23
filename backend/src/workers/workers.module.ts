import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WalletsModule } from '../wallets/wallets.module';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { WorkersController } from './workers.controller';
import { WorkersService } from './workers.service';
import { WorkerProfile } from './worker-profile.entity';
import { Booking } from '../bookings/booking.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([WorkerProfile, TalentProfile, ProfessionalSkill, Booking]),
    WalletsModule
  ],
  controllers: [WorkersController],
  providers: [WorkersService],
  exports: [WorkersService],
})
export class WorkersModule {}
