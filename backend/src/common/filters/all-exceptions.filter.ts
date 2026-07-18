import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';
import { QueryFailedError } from 'typeorm';

/**
 * Global catch-all exception filter.
 *
 * Goals (PENDING_WORK 6.3):
 *  - Return a CONSISTENT error envelope for every failure
 *    ({ statusCode, error, message, path, timestamp }).
 *  - NEVER leak stack traces / internal error messages to the client on 5xx —
 *    unknown errors collapse to a generic "Internal server error" message while
 *    the real detail is logged server-side only.
 *  - Preserve the `message` field shape that the Flutter client already parses
 *    from Nest's default HttpException responses (string OR string[]).
 *  - Map TypeORM database constraint violations to semantic 4xx codes with a
 *    generic, SQL-free message (the raw driver error — table/column names, the
 *    offending value — is logged server-side only, never returned to the client).
 */

/**
 * Postgres SQLSTATE codes for the constraint violations we surface as 4xx.
 * Anything not listed stays a generic 500 so we never leak unexpected DB detail.
 */
const PG_CONSTRAINT_MAP: Record<string, { status: HttpStatus; error: string; message: string }> = {
  '23505': { status: HttpStatus.CONFLICT, error: 'Conflict', message: 'Resource already exists.' },
  '23503': { status: HttpStatus.BAD_REQUEST, error: 'Bad Request', message: 'A referenced resource does not exist.' },
  '23502': { status: HttpStatus.BAD_REQUEST, error: 'Bad Request', message: 'A required field is missing.' },
  '23514': { status: HttpStatus.BAD_REQUEST, error: 'Bad Request', message: 'A value failed a database constraint.' },
};

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let statusCode = HttpStatus.INTERNAL_SERVER_ERROR;
    let message: string | string[] = 'Internal server error';
    let error = 'Internal Server Error';

    if (exception instanceof HttpException) {
      statusCode = exception.getStatus();
      const res = exception.getResponse();
      if (typeof res === 'string') {
        message = res;
      } else if (res && typeof res === 'object') {
        const body = res as Record<string, unknown>;
        if (body.message !== undefined) {
          message = body.message as string | string[];
        }
        if (typeof body.error === 'string') {
          error = body.error;
        }
      }
      if (error === 'Internal Server Error') {
        error = exception.name.replace(/Exception$/, '') || 'Error';
      }
    } else if (exception instanceof QueryFailedError) {
      // TypeORM wraps the driver error; the PG SQLSTATE lives on `.code`
      // (older typeorm copies it onto the QueryFailedError itself) or on
      // `.driverError.code`. Map known constraint codes to a 4xx with a
      // generic message — the raw SQL detail is only logged below, never sent.
      const driver = (exception as { driverError?: { code?: string } }).driverError;
      const code = (exception as unknown as { code?: string }).code ?? driver?.code;
      const mapped = code ? PG_CONSTRAINT_MAP[code] : undefined;
      if (mapped) {
        statusCode = mapped.status;
        error = mapped.error;
        message = mapped.message;
      }
      // Unmapped DB errors fall through as a generic 500 (no leak).
    }

    // Log full detail server-side. Only 5xx carry the stack (genuine faults);
    // 4xx are expected client errors and logged as warnings without a trace.
    if (statusCode >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `${request.method} ${request.url} -> ${statusCode}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    } else {
      this.logger.warn(
        `${request.method} ${request.url} -> ${statusCode}: ${
          Array.isArray(message) ? message.join(', ') : message
        }`,
      );
    }

    response.status(statusCode).json({
      statusCode,
      error,
      message,
      path: request.url,
      timestamp: new Date().toISOString(),
    });
  }
}
