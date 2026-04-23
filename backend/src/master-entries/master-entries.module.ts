import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MasterEntry } from './master-entry.entity';
import { MasterEntriesService } from './master-entries.service';
import { MasterEntriesController } from './master-entries.controller';

@Module({
  imports: [TypeOrmModule.forFeature([MasterEntry])],
  providers: [MasterEntriesService],
  controllers: [MasterEntriesController],
  exports: [MasterEntriesService]
})
export class MasterEntriesModule {}
