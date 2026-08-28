import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TalentProfile } from './talent-profile.entity';
import { ProfessionalSkill } from './professional-skill.entity';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { TalentController } from './talent.controller';
import { TalentService } from './talent.service';
import { AadhaarKycService } from './aadhaar-kyc.service';
import { WorkersModule } from '../workers/workers.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([TalentProfile, ProfessionalSkill, WorkerProfile]),
    WorkersModule,
  ],
  controllers: [TalentController],
  providers: [TalentService, AadhaarKycService],
  exports: [TalentService],
})
export class TalentModule {}
