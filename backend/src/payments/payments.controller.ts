import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Post,
  RawBodyRequest,
  Req,
  UseGuards,
} from '@nestjs/common';
import { SkipThrottle, Throttle } from '@nestjs/throttler';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { PaymentsService } from './payments.service';
import { CreateRechargeOrderDto } from './dto/create-recharge-order.dto';

@Controller('payments')
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  /** Public: lets the picker render correctly even in guest/demo browse. */
  @Get('gateway-status')
  getGatewayStatus() {
    return this.paymentsService.getGatewayStatus();
  }

  /**
   * Razorpay wallet recharge, step 1: create the server-side order the
   * Checkout must reference. Crediting happens ONLY via the webhook below.
   */
  @Post('recharge/order')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  createRechargeOrder(@Req() req: any, @Body() body: CreateRechargeOrderDto) {
    return this.paymentsService.createRechargeOrder(
      req.user.userId,
      body.amount,
    );
  }

  /**
   * Worker period-fee checkout ("N jobs, then pay") — direct Razorpay
   * payment, no wallet. Price comes from Master Entries server-side; the
   * webhook resets the worker's job counter on capture.
   */
  @Post('period-fee/order')
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { ttl: 60_000, limit: 20 } })
  createPeriodFeeOrder(@Req() req: any) {
    return this.paymentsService.createPeriodFeeOrder(req.user.userId);
  }

  /**
   * PUBLIC Razorpay webhook (payment.captured / order.paid). Auth is the
   * HMAC signature over the RAW body — requires rawBody:true in main.ts.
   * Always fast-200s handled/duplicate deliveries; 403 on bad signature;
   * 5xx only when crediting fails (so Razorpay retries).
   * SkipThrottle: provider retries must never hit 429.
   */
  @Post('webhook')
  @HttpCode(200)
  @SkipThrottle()
  webhook(
    @Req() req: RawBodyRequest<any>,
    @Headers('x-razorpay-signature') signature?: string,
  ) {
    return this.paymentsService.handleWebhook(req.rawBody, signature);
  }
}
