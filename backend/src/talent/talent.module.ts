import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TalentProfile } from './talent-profile.entity';
import { ProfessionalSkill } from './professional-skill.entity';
import { TalentController } from './talent.controller';
import { TalentService } from './talent.service';

@Module({
  imports: [TypeOrmModule.forFeature([TalentProfile, ProfessionalSkill])],
  controllers: [TalentController],
  providers: [TalentService],
  exports: [TalentService],
})
export class TalentModule {}
