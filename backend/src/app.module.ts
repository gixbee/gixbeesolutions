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
import { WorkerStrike } from './workers/worker-strike.entity';
import { RentalItem } from './rentals/rental-item.entity';
import { RentalReservation } from './rentals/rental-reservation.entity';
import { JobPost } from './hiring/job-post.entity';
import { JobApplication } from './hiring/job-application.entity';
import { JobPreference } from './hiring/matching/job-preference.entity';
import { HiringRequest } from './hiring/matching/hiring-request.entity';
import { HiringInterest } from './hiring/matching/hiring-interest.entity';
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
import { MessagesModule } from './messages/messages.module';
import { Message } from './messages/message.entity';
import { PaymentsModule } from './payments/payments.module';
import { PaymentOrder } from './payments/payment-order.entity';
import { FavouritesModule } from './favourites/favourites.module';
import { Favourite } from './favourites/favourite.entity';
import { AddressesModule } from './addresses/addresses.module';
import { Address } from './addresses/address.entity';
import { CitiesModule } from './cities/cities.module';
import { City } from './cities/city.entity';
import { SupportModule } from './support/support.module';
import { SupportTicket } from './support/support-ticket.entity';
import { AdminStaff } from './admin-staff/admin-staff.entity';
import { UploadController } from './uploads/upload.controller';
import { AdminStaffModule } from './admin-staff/admin-staff.module';
import { OutboxEvent } from './outbox/outbox-event.entity';
import { SystemLogsModule } from './system-logs/system-logs.module';
import { SystemLog } from './system-logs/system-log.entity';
import { SystemMetricsModule } from './system-metrics/system-metrics.module';
import { BillingModule } from './billing/billing.module';
import { JobCredit } from './billing/job-credit.entity';
import { CreditTransaction } from './billing/credit-transaction.entity';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),

    // Global default: 120 req/min per IP. Auth routes override tighter via
    // @Throttle. Razorpay webhook uses @SkipThrottle so provider retries
    // are never 429'd. (Previously 100000 — effectively unlimited.)
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60_000,
        limit: 120,
      },
    ]),

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
            User,
            Booking,
            WalletTransaction,
            WorkerProfile,
            WorkerStrike,
            RentalItem,
            RentalReservation,
            JobPost,
            JobApplication,
            JobPreference,
            HiringRequest,
            HiringInterest,
            Business,
            TalentProfile,
            ProfessionalSkill,
            MasterEntry,
            Message,
            Favourite,
            Address,
            City,
            SupportTicket,
            AdminStaff,
            OutboxEvent,
            SystemLog,
            PaymentOrder,
            JobCredit,
            CreditTransaction,
          ],
          synchronize: !isProduction, // auto-sync only in development
          migrations: [__dirname + '/migrations/**/*{.ts,.js}'],
          migrationsRun: isProduction, // run migrations automatically in prod
          logging: !isProduction,
          // App-side pg pool. With PgBouncer in front (transaction pooling),
          // these are cheap client connections to the pooler — not real
          // Postgres backends — so it's safe to raise above the pg default
          // of 10. PgBouncer multiplexes them onto DEFAULT_POOL_SIZE real
          // server connections.
          //
          // TRANSACTION pooling means each checkout may land on a different
          // server backend. Do NOT use session-scoped Postgres features:
          // LISTEN/NOTIFY, session advisory locks, or named PREPARE that
          // outlive a transaction. Keep work inside TypeORM transactions /
          // single queries.
          //
          // Do NOT set `options: '-c statement_timeout=...'` here — PgBouncer
          // rejects that startup parameter. Timeout is enforced on Postgres
          // itself via docker-compose (`postgres -c statement_timeout=60s`).
          extra: {
            max: 50,
            idleTimeoutMillis: 30_000,
            connectionTimeoutMillis: 10_000,
            application_name: 'gixbee-backend',
          },
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
    MessagesModule,
    PaymentsModule,
    FavouritesModule,
    AddressesModule,
    BillingModule,
    CitiesModule,
    SupportModule,
    AdminStaffModule,
    SystemLogsModule,
    SystemMetricsModule,

    // Serve uploaded files as static assets
    ServeStaticModule.forRoot({
      rootPath: join(__dirname, '..', 'uploads'),
      serveRoot: '/uploads',
    }),
  ],
  controllers: [AppController, UploadController],
  providers: [AppService, { provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
