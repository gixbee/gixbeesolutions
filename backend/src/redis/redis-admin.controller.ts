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

  @Get('keys')
  async getKeys(@Query('pattern') pattern?: string) {
    const searchPattern = pattern || '*';
    const keys = await this.redisService.getAdminKeys(searchPattern);
    return { keys };
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
