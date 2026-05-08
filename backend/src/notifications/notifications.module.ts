import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule } from '@nestjs/config';
import { NotificationsService } from './notifications.service';
import { NotificationsController } from './notifications.controller';
import { User } from '../users/user.entity';
import { RedisModule } from '../redis/redis.module';

@Module({
  imports: [
    ConfigModule,
    // Provides @InjectRepository(User) for FCM token lookup
    TypeOrmModule.forFeature([User]),
    // Provides RedisService for FCM token caching (fast path)
    RedisModule,
  ],
  controllers: [NotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
