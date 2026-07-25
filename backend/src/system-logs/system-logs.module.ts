import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { TypeOrmModule } from '@nestjs/typeorm';
import { SystemLog } from './system-log.entity';
import { SystemLogsService } from './system-logs.service';
import { SystemLogsController } from './system-logs.controller';
import { ApiLoggingInterceptor } from './api-logging.interceptor';

/**
 * Persistent request/error logging + the admin portal's Logs page API.
 * Providing APP_INTERCEPTOR here registers ApiLoggingInterceptor globally
 * (with DI) — no change needed in main.ts.
 */
@Module({
  imports: [TypeOrmModule.forFeature([SystemLog])],
  providers: [
    SystemLogsService,
    { provide: APP_INTERCEPTOR, useClass: ApiLoggingInterceptor },
  ],
  controllers: [SystemLogsController],
  exports: [SystemLogsService],
})
export class SystemLogsModule {}
