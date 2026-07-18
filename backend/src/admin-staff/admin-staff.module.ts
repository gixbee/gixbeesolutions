import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AdminStaff } from './admin-staff.entity';
import { AdminStaffService } from './admin-staff.service';
import { AdminStaffController } from './admin-staff.controller';

@Module({
  imports: [TypeOrmModule.forFeature([AdminStaff])],
  providers: [AdminStaffService],
  controllers: [AdminStaffController],
  exports: [AdminStaffService],
})
export class AdminStaffModule {}
