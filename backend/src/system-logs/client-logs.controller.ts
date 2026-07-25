import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Post,
  Req,
} from '@nestjs/common';
import { Request } from 'express';
import { SystemLogsService } from './system-logs.service';
import { SystemLogLevel, SystemLogType } from './system-log.entity';
import { ClientLogDto } from './dto/client-log.dto';

/**
 * Public endpoint for the Flutter app to report client-side crashes.
 * No auth guard — the app must be able to report errors even when the
 * JWT has expired (which is itself a common crash scenario).
 *
 * Rate-limited by default via the global throttle guard in main.ts.
 * Reports are stored as SystemLog rows with type APP_CRASH so they
 * appear alongside server errors in the admin portal's Logs page.
 */
@Controller('client-logs')
export class ClientLogsController {
  constructor(private readonly logs: SystemLogsService) {}

  @Post()
  @HttpCode(HttpStatus.NO_CONTENT)
  report(@Body() dto: ClientLogDto, @Req() req: Request): void {
    const ip =
      (req.headers['x-forwarded-for'] as string)?.split(',')[0]?.trim() ||
      req.ip ||
      null;

    // Try to extract userId from JWT if present (best-effort, no guard).
    const userId: string | null =
      (req as unknown as { user?: { userId?: string } }).user?.userId ?? null;

    const messageParts: string[] = [dto.error];
    if (dto.errorType) messageParts.unshift(`[${dto.errorType}]`);
    if (dto.screen) messageParts.push(`@ ${dto.screen}`);

    const detailParts: string[] = [];
    if (dto.stackTrace) detailParts.push(dto.stackTrace);
    if (dto.appVersion) detailParts.push(`App version: ${dto.appVersion}`);
    if (dto.device) detailParts.push(`Device: ${dto.device}`);

    this.logs.record({
      level: SystemLogLevel.ERROR,
      type: SystemLogType.APP_CRASH,
      method: 'APP',
      path: dto.screen ?? '/unknown',
      statusCode: null,
      durationMs: null,
      userId,
      ip,
      message: messageParts.join(' ').slice(0, 500),
      detail: detailParts.join('\n').slice(0, 8000) || null,
    });
  }
}
