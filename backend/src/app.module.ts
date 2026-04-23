import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bull';
import { ServeStaticModule } from '@nestjs/serve-static';
import { join } from 'path';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { User } from './users/user.entity';
import { Booking } from './bookings/booking.entity';
import { WalletTransaction } from './wallets/wallet-transaction.entity';
import { WorkerProfile } from './workers/worker-profile.entity';
import { RentalItem } from './rentals/rental-item.entity';
import { RentalReservation } from './rentals/rental-reservation.entity';
import { JobPost } from './hiring/job-post.entity';
import { JobApplication } from './hiring/job-application.entity';
import { Business } from './businesses/business.entity';
import { TalentProfile } from './talent/talent-profile.entity';
import { ProfessionalSkill } from './talent/professional-skill.entity';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { WorkerEngineModule } from './worker-engine/worker-engine.module';
import { BookingsModule } from './bookings/bookings.module';
import { WalletsModule } from './wallets/wallets.module';
import { WorkersModule } from './workers/workers.module';
import { NotificationsModule } from './notifications/notifications.module';
import { RedisModule } from './redis/redis.module';
import { RentalsModule } from './rentals/rentals.module';
import { HiringModule } from './hiring/hiring.module';
import { BusinessesModule } from './businesses/businesses.module';
import { TalentModule } from './talent/talent.module';
import { MasterEntriesModule } from './master-entries/master-entries.module';
import { MasterEntry } from './master-entries/master-entry.entity';
// FirebaseModule removed — using OneSignal via NotificationsModule
import { UploadController } from './uploads/upload.controller';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    ThrottlerModule.forRoot([{
      ttl: 60000,
      limit: 100,
    }]),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        host: configService.get<string>('DATABASE_HOST'),
        port: configService.get<number>('DATABASE_PORT'),
        username: configService.get<string>('DATABASE_USER'),
        password: configService.get<string>('DATABASE_PASSWORD'),
        database: configService.get<string>('DATABASE_NAME'),
        entities: [User, Booking, WalletTransaction, WorkerProfile, RentalItem, RentalReservation, JobPost, JobApplication, Business, TalentProfile, ProfessionalSkill, MasterEntry],
        synchronize: configService.get('NODE_ENV') === 'development', // DEFECT-011: env-controlled
      }),
      inject: [ConfigService],
    }),
    BullModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (configService: ConfigService) => ({
        redis: {
          host: configService.get<string>('REDIS_HOST'),
          port: configService.get<number>('REDIS_PORT'),
        },
      }),
      inject: [ConfigService],
    }),
    UsersModule,
    AuthModule,
    WorkerEngineModule,
    BookingsModule,
    WalletsModule,
    WorkersModule,
    NotificationsModule,
    RedisModule,
    RentalsModule,
    HiringModule,
    BusinessesModule,
    TalentModule,
    MasterEntriesModule,

    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', 'uploads'),
      serveRoot: '/uploads',
    }),
  ],
  controllers: [AppController, UploadController],
  providers: [
    AppService,
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
