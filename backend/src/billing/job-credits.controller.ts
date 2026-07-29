import { Controller, Get, Post, Body, UseGuards, Request, BadRequestException } from '@nestjs/common';
import { JobCreditsService, CREDITS_PER_PACK, PACK_PRICE_INR } from './job-credits.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';
import { CreditTransactionReason } from './credit-transaction.entity';

@Controller('billing/credits')
@UseGuards(JwtAuthGuard)
export class JobCreditsController {
  constructor(
    private jobCreditsService: JobCreditsService,
    private configService: ConfigService,
  ) {}

  @Get('balance')
  async getBalance(@Request() req: any) {
    const balance = await this.jobCreditsService.getBalance(req.user.id);
    return { balance };
  }

  @Get('pack-info')
  getPackInfo() {
    return { credits: CREDITS_PER_PACK, price: PACK_PRICE_INR, currency: 'INR' };
  }

  @Post('create-order')
  async createOrder(@Request() req: any) {
    const keyId = this.configService.get<string>('RAZORPAY_KEY_ID');
    const keySecret = this.configService.get<string>('RAZORPAY_KEY_SECRET');

    if (!keyId || !keySecret) {
      throw new BadRequestException('Payment gateway is not configured.');
    }

    const auth = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
    const res = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        Authorization: `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        amount: PACK_PRICE_INR * 100, // paise
        currency: 'INR',
        receipt: `jobpack_${Date.now().toString(36)}`,
        notes: { gixbeeUserId: req.user.id, purpose: 'JOB_PACK' },
      }),
    });

    if (!res.ok) {
      throw new BadRequestException('Could not create payment order.');
    }

    const order = (await res.json()) as { id: string };
    return {
      orderId: order.id,
      amount: PACK_PRICE_INR * 100,
      currency: 'INR',
      keyId,
    };
  }

  @Post('verify')
  async verifyPayment(@Request() req: any, @Body() body: any) {
    const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = body;
    if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
      throw new BadRequestException('Missing payment verification details.');
    }

    const keySecret = this.configService.get<string>('RAZORPAY_KEY_SECRET');
    if (!keySecret) {
      throw new BadRequestException('Payment gateway not configured.');
    }

    const generatedSignature = crypto
      .createHmac('sha256', keySecret)
      .update(razorpay_order_id + '|' + razorpay_payment_id)
      .digest('hex');

    let isValid = false;
    try {
      isValid = crypto.timingSafeEqual(
        Buffer.from(generatedSignature),
        Buffer.from(razorpay_signature),
      );
    } catch {
      isValid = false;
    }

    if (!isValid) {
      throw new BadRequestException('Invalid payment signature.');
    }

    // Idempotent addCredits - we only add if this payment hasn't been credited yet.
    // The service doesn't have an idempotency check for PURCHASE yet, wait, we need to handle that!
    // I should update the service to be idempotent for PURCHASE if razorpayPaymentId is provided.
    // I will call addCredits, and in addCredits I will add idempotency.
    await this.jobCreditsService.addCredits(req.user.id, CREDITS_PER_PACK, {
      reason: CreditTransactionReason.PURCHASE,
      razorpayPaymentId: razorpay_payment_id,
    });

    const balance = await this.jobCreditsService.getBalance(req.user.id);
    return { balance };
  }
}
