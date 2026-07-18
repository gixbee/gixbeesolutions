import { Body, Controller, Get, Post, Req, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PaymentsService } from './payments.service';
import { InitiateUpiDto } from './dto/initiate-upi.dto';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  /** Public: lets the picker render correctly even in guest/demo browse. */
  @Get('gateway-status')
  getGatewayStatus() {
    return this.paymentsService.getGatewayStatus();
  }

  @Post('upi/initiate')
  @UseGuards(JwtAuthGuard)
  initiateUpi(
    @Req() req: any,
    @Body() body: InitiateUpiDto,
  ) {
    return this.paymentsService.initiateUpiPayment(req.user.userId, body);
  }
}
