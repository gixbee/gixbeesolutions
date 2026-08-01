import {
  Controller,
  Get,
  Query,
  UseGuards,
  BadRequestException,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { RedisService } from './redis.service';

@Controller('redis/admin')
@UseGuards(JwtAuthGuard, AdminGuard)
@RequireAdminPage('monitoring')
export class RedisAdminController {
  constructor(private readonly redisService: RedisService) {}

  /** `truncated` tells the UI the scan hit its cap and the pattern needs narrowing. */
  @Get('keys')
  async getKeys(
    @Query('pattern') pattern?: string,
    @Query('limit') limit?: string,
  ) {
    const searchPattern = pattern || '*';
    const parsed = Number(limit);
    const cap =
      Number.isFinite(parsed) && parsed > 0 ? Math.min(parsed, 5000) : 1000;
    const keys = await this.redisService.getAdminKeys(searchPattern, cap);
    return { keys, truncated: keys.length >= cap };
  }

  @Get('key')
  async getKeyDetails(@Query('id') keyId?: string) {
    if (!keyId) {
      throw new BadRequestException('Key ID is required');
    }
    const details = await this.redisService.getAdminKeyDetails(keyId);
    return details;
  }
}
