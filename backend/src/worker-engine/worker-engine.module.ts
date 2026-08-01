import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { Booking } from '../bookings/booking.entity';
import { WorkerGateway } from './worker.gateway';

@Module({
  imports: [AuthModule, TypeOrmModule.forFeature([Booking])],
  providers: [WorkerGateway],
})
export class WorkerEngineModule {}
