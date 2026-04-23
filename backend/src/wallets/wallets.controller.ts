import { Controller, Get, UseGuards, Req } from '@nestjs/common';
import { WalletsService } from './wallets.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('wallets')
@UseGuards(JwtAuthGuard)
export class WalletsController {
  constructor(private readonly walletsService: WalletsService) {}

  @Get('balance')
  async getBalance(@Req() req: any) {
    const balance = await this.walletsService.getBalance(req.user.userId);
    return { balance };
  }

  @Get('transactions')
  async getTransactions(@Req() req: any) {
    return this.walletsService.getTransactions(req.user.userId);
  }
}
