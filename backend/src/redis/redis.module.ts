import { Global, Module } from '@nestjs/common';
import { RedisService } from './redis.service';
import { ConfigModule } from '@nestjs/config';
import { RedisAdminController } from './redis-admin.controller';

@Global()
@Module({
  imports: [ConfigModule],
  providers: [RedisService],
  controllers: [RedisAdminController],
  exports: [RedisService],
})
export class RedisModule {}
