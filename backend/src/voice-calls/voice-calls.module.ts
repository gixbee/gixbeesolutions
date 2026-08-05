import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Booking } from '../bookings/booking.entity';
import { AuthModule } from '../auth/auth.module';
import { RedisModule } from '../redis/redis.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { VoiceCallsService } from './voice-calls.service';
import { VoiceCallsGateway } from './voice-calls.gateway';
import { VoiceCallsController } from './voice-calls.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([Booking]),
    AuthModule,
    RedisModule,
    NotificationsModule,
  ],
  controllers: [VoiceCallsController],
  providers: [VoiceCallsService, VoiceCallsGateway],
  exports: [VoiceCallsService],
})
export class VoiceCallsModule {}
