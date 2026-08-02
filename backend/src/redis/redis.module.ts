import { Global, Module } from '@nestjs/common';
import { RedisService } from './redis.service';
import { ConfigModule } from '@nestjs/config';
import { RedisAdminController } from './redis-admin.controller';
import { RedisBookingStateService } from './redis-booking-state.service';
import { RedisWorkerIndexService } from './redis-worker-index.service';
import { RedisAdminService } from './redis-admin.service';

@Global()
@Module({
  imports: [ConfigModule],
  providers: [
    RedisService,
    RedisBookingStateService,
    RedisWorkerIndexService,
    RedisAdminService,
  ],
  controllers: [RedisAdminController],
  exports: [
    RedisService,
    RedisBookingStateService,
    RedisWorkerIndexService,
    RedisAdminService,
  ],
})
export class RedisModule {}
