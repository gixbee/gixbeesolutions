import {
  CallHandler,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, throwError } from 'rxjs';
import { catchError, tap } from 'rxjs/operators';
import { Request, Response } from 'express';
import { QueryFailedError } from 'typeorm';
import { SystemLogsService } from './system-logs.service';
import { SystemLogLevel, SystemLogType } from './system-log.entity';

/**
 * Global HTTP interceptor that persists failures for the admin Logs page:
 *  - HttpException (4xx) → level WARN
 *  - 5xx / DB failures (QueryFailedError) → level ERROR with driver detail
 *  - anything else thrown → level ERROR with stack trace
 * Successful 2xx/3xx are not written — they hid real errors and flooded Postgres.
 *
 * Runs BEFORE AllExceptionsFilter in the error path (interceptors wrap the
 * handler), so the filter's client-facing envelope is untouched — this only
 * records. Registered via APP_INTERCEPTOR in SystemLogsModule.
 */

/** Paths we never persist (noise / recursion / high-frequency admin polls). */
const SKIP_PREFIXES = [
  '/system-logs',
  '/system-metrics',
  '/uploads',
  '/favicon',
  '/admin-user-list/summary',
];

/** Exact GET paths that spam logs when the dashboard is left open. */
const SKIP_EXACT_GET = new Set(['/', '/health', '/healthz']);

@Injectable()
export class ApiLoggingInterceptor implements NestInterceptor {
  constructor(private readonly logs: SystemLogsService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();

    const req = context.switchToHttp().getRequest<Request>();
    const url = req.originalUrl || req.url || '';
    const pathOnly = url.split('?')[0];
    if (SKIP_PREFIXES.some((p) => pathOnly.startsWith(p))) return next.handle();
    if (req.method === 'GET' && SKIP_EXACT_GET.has(pathOnly))
      return next.handle();

    const started = Date.now();
    const method = req.method;
    const userId: string | null =
      (req as unknown as { user?: { userId?: string } }).user?.userId ?? null;
    const ip =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
      req.ip ||
      null;
    const baseType = pathOnly.startsWith('/auth')
      ? SystemLogType.AUTH
      : SystemLogType.API;

    return next.handle().pipe(
      tap(() => {
        const res = context.switchToHttp().getResponse<Response>();
        if (res.statusCode < 400) return;
        this.logs.record({
          level:
            res.statusCode >= 500
              ? SystemLogLevel.ERROR
              : SystemLogLevel.WARN,
          type: baseType,
          method,
          path: url,
          statusCode: res.statusCode,
          durationMs: Date.now() - started,
          userId,
          ip,
        });
      }),
      catchError((err: unknown) => {
        let statusCode = HttpStatus.INTERNAL_SERVER_ERROR as number;
        let type = baseType;
        let message = 'Internal server error';
        let detail: string | null = null;

        if (err instanceof HttpException) {
          statusCode = err.getStatus();
          const res = err.getResponse();
          message =
            typeof res === 'string'
              ? res
              : Array.isArray((res as { message?: unknown }).message)
                ? (res as { message: string[] }).message.join('; ')
                : String((res as { message?: unknown }).message ?? err.message);
          if (statusCode >= 500) detail = err.stack ?? null;
        } else if (err instanceof QueryFailedError) {
          type = SystemLogType.DB;
          message = err.message;
          const drv = (
            err as { driverError?: { code?: string; detail?: string } }
          ).driverError;
          detail = [
            drv?.code ? `SQLSTATE ${drv.code}` : null,
            drv?.detail ?? null,
            err.stack ?? null,
          ]
            .filter(Boolean)
            .join('\n');
        } else if (err instanceof Error) {
          message = err.message;
          detail = err.stack ?? null;
        } else {
          message = String(err);
        }

        this.logs.record({
          level: statusCode >= 500 ? SystemLogLevel.ERROR : SystemLogLevel.WARN,
          type,
          method,
          path: url,
          statusCode,
          durationMs: Date.now() - started,
          userId,
          ip,
          message,
          detail,
        });

        return throwError(() => err);
      }),
    );
  }
}
