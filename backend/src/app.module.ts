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
import { UploadController } from './uploads/upload.controller';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),

    ThrottlerModule.forRoot([{ ttl: 60000, limit: 100 }]),

    // ── Database ───────────────────────────────────────────────────────────
    // Supports two connection modes:
    //   1. DATABASE_URL  — used by Railway / cloud deployments (single env var)
    //   2. Individual vars — used by Docker Compose (host/port/user/pass/name)
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => {
        const isProduction = config.get('NODE_ENV') === 'production';
        const databaseUrl = config.get<string>('DATABASE_URL');

        const baseConfig = {
          type: 'postgres' as const,
          entities: [
            User, Booking, WalletTransaction, WorkerProfile,
            RentalItem, RentalReservation, JobPost, JobApplication,
            Business, TalentProfile, ProfessionalSkill, MasterEntry,
          ],
          synchronize: !isProduction,   // auto-sync only in development
          migrations: [__dirname + '/migrations/**/*{.ts,.js}'],
          migrationsRun: isProduction,  // run migrations automatically in prod
          logging: !isProduction,
        };

        if (databaseUrl) {
          // Cloud / Railway mode — single DATABASE_URL
          return {
            ...baseConfig,
            url: databaseUrl,
            ssl: isProduction ? { rejectUnauthorized: false } : false,
          };
        }

        // Docker Compose mode — individual vars injected by docker-compose.yml
        return {
          ...baseConfig,
          host: config.get<string>('DATABASE_HOST', 'postgres'),
          port: config.get<number>('DATABASE_PORT', 5432),
          username: config.get<string>('DATABASE_USER', 'postgres'),
          password: config.get<string>('DATABASE_PASSWORD'),
          database: config.get<string>('DATABASE_NAME', 'gixbee'),
          ssl: false,
        };
      },
      inject: [ConfigService],
    }),

    // ── Redis / Bull ───────────────────────────────────────────────────────
    // Supports REDIS_URL (cloud) or individual REDIS_HOST/PORT/PASSWORD (Docker)
    BullModule.forRootAsync({
      imports: [ConfigModule],
      useFactory: (config: ConfigService) => {
        const redisUrl = config.get<string>('REDIS_URL');

        if (redisUrl) {
          // Cloud / Upstash mode
          return { redis: redisUrl };
        }

        // Docker Compose mode
        return {
          redis: {
            host: config.get<string>('REDIS_HOST', 'redis'),
            port: config.get<number>('REDIS_PORT', 6379),
            password: config.get<string>('REDIS_PASSWORD'),
          },
        };
      },
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

    // Serve uploaded files as static assets
    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', 'uploads'),
      serveRoot: '/uploads',
    }),
  ],
  controllers: [AppController, UploadController],
  providers: [
    AppService,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
