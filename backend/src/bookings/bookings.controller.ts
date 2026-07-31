import {
  Controller,
  Post,
  Get,
  Patch,
  Param,
  Body,
  Query,
  UseGuards,
  Req,
  NotFoundException,
} from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AdminGuard } from '../auth/admin.guard';
import { RequireAdminPage } from '../auth/require-admin-page.decorator';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import {
  CreateBookingDto,
  CreateInstantRequestDto,
} from './dto/create-booking.dto';
import {
  UpdateBookingStatusDto,
  CancelBookingDto,
  ConfirmOtpDto,
  SubmitRatingDto,
  ReportDisputeDto,
  ResolveDisputeDto,
  MarkPaidDto,
} from './dto/booking-actions.dto';

@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class BookingsController {
  constructor(
    private readonly bookingsService: BookingsService,
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
  ) {}

  @Post()
  async create(@Req() req, @Body() body: CreateBookingDto) {
    return this.bookingsService.createBooking({
      customer: { id: req.user.userId } as any,
      operator: { id: body.workerId } as any,
      skill: body.skill,
      serviceLocation: body.serviceLocation,
      serviceLat: body.serviceLat,
      serviceLng: body.serviceLng,
      onSiteContact: body.onSiteContact,
      scheduledAt: new Date(body.scheduledAt),
      amount: body.amount,
      type: body.type,
      addressId: body.addressId,
      paymentMethod: body.paymentMethod || 'WALLET',
    });
  }

  // v126 broadcast dispatch: no worker chosen — all nearby live pros with the
  // skill are notified, first accept wins. Returns { booking, notified } so
  // the app can go straight to the no-workers screen when notified === 0.
  @Post('instant')
  async createInstantRequest(
    @Req() req,
    @Body() body: CreateInstantRequestDto,
  ) {
    return this.bookingsService.createBroadcastBooking(req.user.userId, {
      skill: body.skill,
      serviceLocation: body.serviceLocation,
      serviceLat: body.serviceLat,
      serviceLng: body.serviceLng,
      amount: body.amount,
      description: body.description,
      preferredLanguages: body.preferredLanguages,
      addressId: body.addressId,
      paymentMethod: body.paymentMethod,
      onSiteContact: body.onSiteContact,
    });
  }

  // ── Admin: portal monitor + disputes (AdminGuard) ─────────────────────────

  @Get('admin/all')
  @UseGuards(AdminGuard)
  @RequireAdminPage('bookings')
  async adminListBookings(
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.bookingsService.adminListBookings(
      status || undefined,
      parseInt(page || '1') || 1,
      parseInt(limit || '50') || 50,
    );
  }

  @Get('admin/disputes')
  @UseGuards(AdminGuard)
  @RequireAdminPage('disputes')
  async adminDisputes(
    @Query('open') open?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const pageNum = parseInt(page || '1') || 1;
    const limitNum = Math.min(100, parseInt(limit || '50') || 50);
    return this.bookingsService.getDisputes(open === 'true', pageNum, limitNum);
  }

  @Patch('admin/disputes/:id/resolve')
  @UseGuards(AdminGuard)
  @RequireAdminPage('disputes')
  async adminResolveDispute(
    @Param('id') id: string,
    @Body() body: ResolveDisputeDto,
  ) {
    return this.bookingsService.resolveDispute(id, body.resolution);
  }

  @Get('my')
  async getMyBookings(
    @Req() req,
    @Query('status') status?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const pageNum = parseInt(page || '1') || 1;
    const limitNum = parseInt(limit || '50') || 50;
    return this.bookingsService.findMyBookings(
      req.user.userId,
      status,
      pageNum,
      limitNum,
    );
  }

  // Worker polls this to discover incoming job requests (FCM fallback)
  @Get('pending')
  async getPendingBookings(@Req() req) {
    return this.bookingsService.findPendingForWorker(req.user.userId);
  }

  @Patch(':id/status')
  async updateStatus(
    @Param('id') id: string,
    @Req() req,
    @Body() body: UpdateBookingStatusDto,
  ) {
    // SECURITY FIX: was unscoped — anyone could set any booking to COMPLETED.
    await this.bookingsService.assertParticipant(id, req.user.userId);
    return this.bookingsService.updateStatus(id, body.status);
  }

  // Customer cancellation with reason + wallet refund
  @Patch(':id/cancel')
  async cancel(
    @Param('id') id: string,
    @Req() req,
    @Body() body: CancelBookingDto,
  ) {
    await this.bookingsService.assertParticipant(id, req.user.userId);
    const source = req.user.role === 'CUSTOMER' ? 'customer' : 'operator';
    return this.bookingsService.cancelBooking(
      id,
      body?.reason ?? 'Not specified',
      source,
    );
  }

  // ─── OTP GATES ──────────────────────────────────────────

  @Post(':id/arrival')
  async confirmArrival(
    @Param('id') id: string,
    @Req() req,
    @Body() body: ConfirmOtpDto,
  ) {
    // SECURITY FIX: participants only — was open to 4-digit OTP brute force
    // by any authenticated user.
    await this.bookingsService.assertParticipant(id, req.user.userId);
    return this.bookingsService.verifyArrivalOtp(id, body.otp);
  }

  @Post(':id/completion')
  async confirmCompletion(
    @Param('id') id: string,
    @Req() req,
    @Body() body: ConfirmOtpDto,
  ) {
    // SECURITY FIX: participants only (see arrival above).
    await this.bookingsService.assertParticipant(id, req.user.userId);
    return this.bookingsService.verifyCompletionOtp(id, body.otp);
  }

  @Patch(':id/refresh-completion-otp')
  async refreshCompletionOtp(@Param('id') id: string, @Req() req) {
    // OTP recipient is the customer — only participants may trigger a resend.
    await this.bookingsService.assertParticipant(id, req.user.userId);
    return this.bookingsService.refreshCompletionOtp(id);
  }

  @Patch(':id/confirm')
  async confirmBooking(@Param('id') id: string, @Req() req) {
    await this.bookingsService.assertParticipant(id, req.user.userId);
    return this.bookingsService.updateStatus(id, BookingStatus.ACCEPTED);
  }

  @Patch(':id/accept')
  async acceptBooking(@Param('id') id: string, @Req() req) {
    try {
      // Customer FCM is sent inside BookingsService.acceptBooking (the
      // stripped return payload previously skipped notification here).
      return await this.bookingsService.acceptBooking(id, req.user.userId);
    } catch (error) {
      console.error('[AcceptBooking] Error:', error);
      throw error;
    }
  }

  @Patch(':id/reject')
  async rejectBooking(@Param('id') id: string, @Req() req) {
    return this.bookingsService.rejectBooking(id, req.user.userId);
  }

  @Get(':id')
  async getBooking(@Param('id') id: string, @Req() req) {
    const booking = await this.bookingsService.getBookingById(id);
    if (!booking) throw new NotFoundException('Booking not found');
    // SECURITY FIX: only participants may read a booking. Previously ANY
    // logged-in user could read customer PII, the service address AND the
    // arrival/completion OTPs — reading the OTP straight out of this response
    // defeated the arrival/completion gates entirely.
    const isParticipant =
      booking.customer?.id === req.user.userId ||
      booking.operator?.id === req.user.userId;
    if (!isParticipant) throw new NotFoundException('Booking not found');
    return booking;
  }

  // Get booking status (for polling). SECURITY FIX: this used to be
  // unscoped and returned the arrivalOtp to anyone — reading it here defeated
  // the arrival gate. Now: participant-only, and the arrivalOtp is ONLY
  // returned to the customer (who displays it for the worker to enter).
  @Get(':id/status')
  async getBookingStatus(@Param('id') id: string, @Req() req) {
    return this.bookingsService.getStatusForParticipant(id, req.user.userId);
  }

  // DEFECT-012 FIX: Send arrival OTP to customer via FCM push
  @Patch(':id/arrive')
  async markArrived(@Param('id') id: string, @Req() req) {
    // SECURITY FIX: was unscoped — any logged-in user could trigger OTP
    // pushes to any customer (spam/social-engineering vector). Only the
    // assigned worker may announce arrival.
    const booking = await this.bookingsService.assertParticipant(
      id,
      req.user.userId,
    );
    if (booking.operator?.id !== req.user.userId) {
      throw new NotFoundException('Booking not found');
    }

    const otp = booking.arrivalOtp;

    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Worker has arrived',
        body: `Arrival OTP: ${otp}. Share this with the worker to begin.`,
      });
    }

    return { message: 'Arrival OTP sent to customer.' };
  }

  // DEFECT-012 FIX: Send completion OTP to customer via FCM push
  @Patch(':id/complete')
  async markComplete(@Param('id') id: string, @Req() req) {
    // SECURITY FIX: assigned worker only (see markArrived above).
    const booking = await this.bookingsService.assertParticipant(
      id,
      req.user.userId,
    );
    if (booking.operator?.id !== req.user.userId) {
      throw new NotFoundException('Booking not found');
    }

    const otp = booking.completionOtp;

    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Job marked as complete',
        body: `Completion OTP: ${otp}. Enter this to confirm and close the job.`,
      });
    }

    return { message: 'Completion OTP sent to customer.' };
  }

  @Patch(':id/mark-paid')
  async markPaid(
    @Param('id') id: string,
    @Req() req,
    @Body() body: MarkPaidDto,
  ) {
    return this.bookingsService.markPaid(id, req.user.userId, body ?? {});
  }

  @Post(':id/rating')
  async submitRating(
    @Param('id') id: string,
    @Req() req,
    @Body() body: SubmitRatingDto,
  ) {
    // SECURITY FIX: was unscoped — anyone could rate any booking. Only the
    // customer may rate the worker.
    const booking = await this.bookingsService.assertParticipant(
      id,
      req.user.userId,
    );
    if (booking.customer?.id !== req.user.userId) {
      throw new NotFoundException('Booking not found');
    }
    return this.bookingsService.submitRating(id, body.rating);
  }

  // v126 parity: worker rates the customer after completion.
  @Post(':id/rate-customer')
  async rateCustomer(
    @Param('id') id: string,
    @Req() req,
    @Body() body: SubmitRatingDto,
  ) {
    return this.bookingsService.rateCustomer(id, req.user.userId, body.rating);
  }

  // ── Pause / resume (v126 Instant Help). Worker asks → customer approves or
  // declines → worker resumes. Status stays ACTIVE; pollers see the pause
  // state via the Redis status payload.
  @Patch(':id/pause-request')
  async requestPause(@Param('id') id: string, @Req() req) {
    return this.bookingsService.requestPause(id, req.user.userId);
  }

  @Patch(':id/pause-approve')
  async approvePause(@Param('id') id: string, @Req() req) {
    return this.bookingsService.respondPause(id, req.user.userId, true);
  }

  @Patch(':id/pause-decline')
  async declinePause(@Param('id') id: string, @Req() req) {
    return this.bookingsService.respondPause(id, req.user.userId, false);
  }

  @Patch(':id/resume')
  async resumeWork(@Param('id') id: string, @Req() req) {
    return this.bookingsService.resumeWork(id, req.user.userId);
  }

  // Persisted now (was log-only): stored on the booking with reporter role
  // + timestamp so support/admin can review.
  @Post(':id/dispute')
  async reportDispute(
    @Param('id') id: string,
    @Req() req,
    @Body() body: ReportDisputeDto,
  ) {
    return this.bookingsService.reportDispute(id, req.user.userId, body.reason);
  }
}
