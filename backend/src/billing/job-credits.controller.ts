import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { JobCreditsService } from './job-credits.service';
import { JobPackPaymentsService } from './job-pack-payments.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('billing/credits')
@UseGuards(JwtAuthGuard)
export class JobCreditsController {
  constructor(
    private readonly jobCreditsService: JobCreditsService,
    private readonly payments: JobPackPaymentsService,
  ) {}

  @Get('balance')
  async getBalance(@Request() req: any) {
    const [balance, creditsPerAccept] = await Promise.all([
      this.jobCreditsService.getBalance(req.user.userId),
      this.jobCreditsService.getCreditsPerAccept(),
    ]);
    return { balance, creditsPerAccept };
  }

  @Get('booking/:bookingId')
  getBookingCreditUsage(
    @Request() req: any,
    @Param('bookingId') bookingId: string,
  ) {
    return this.jobCreditsService.getBookingCreditUsage(
      req.user.userId,
      bookingId,
    );
  }

  @Get('transactions')
  async getTransactions(
    @Request() req: any,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const transactions = await this.jobCreditsService.getTransactions(
      req.user.userId,
      Math.min(100000, Math.max(1, Math.floor(Number(page) || 1))),
      Math.min(100, Math.max(1, Math.floor(Number(limit) || 50))),
    );
    return { transactions };
  }

  @Get('pack-info')
  getPackInfo() {
    return this.jobCreditsService.getPackInfo();
  }

  @Post('create-order')
  createOrder(@Request() req: any) {
    return this.payments.createOrder(req.user.userId);
  }

  @Post('verify')
  verifyPayment(@Request() req: any, @Body() body: Record<string, unknown>) {
    return this.payments.verify(req.user.userId, body);
  }
}
