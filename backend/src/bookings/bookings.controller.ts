import { Controller, Post, Get, Patch, Param, Body, UseGuards, Req, NotFoundException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus, BookingType } from './booking.entity';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NotificationsService } from '../notifications/notifications.service';

@Controller('bookings')
@UseGuards(JwtAuthGuard)
export class BookingsController {
  constructor(
    private readonly bookingsService: BookingsService,
    private readonly notificationsService: NotificationsService,
  ) {}

  @Post()
  async create(@Req() req, @Body() body: {
    workerId: string;
    skill: string;
    serviceLocation: string;
    serviceLat: number;
    serviceLng: number;
    onSiteContact?: { name: string; relation: string; phone: string };
    scheduledAt: string;
    amount: number;
    type: BookingType;
  }) {
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
    });
  }

  @Get('my')
  async getMyBookings(@Req() req) {
    const customerBookings = await this.bookingsService.findAllByUser(req.user.userId, 'customer');
    const operatorBookings = await this.bookingsService.findAllByUser(req.user.userId, 'operator');
    return [...customerBookings, ...operatorBookings];
  }

  // Worker polls this to discover incoming job requests (FCM fallback)
  @Get('pending')
  async getPendingBookings(@Req() req) {
    return this.bookingsService.findPendingForWorker(req.user.userId);
  }

  @Patch(':id/status')
  async updateStatus(@Param('id') id: string, @Body() body: { status: BookingStatus }) {
    return this.bookingsService.updateStatus(id, body.status);
  }

  // ─── OTP GATES ──────────────────────────────────────────

  @Post(':id/arrival')
  async confirmArrival(@Param('id') id: string, @Body() body: { otp: string }) {
    return this.bookingsService.verifyArrivalOtp(id, body.otp);
  }

  @Post(':id/completion')
  async confirmCompletion(@Param('id') id: string, @Body() body: { otp: string }) {
    return this.bookingsService.verifyCompletionOtp(id, body.otp);
  }

  @Patch(':id/refresh-completion-otp')
  async refreshCompletionOtp(@Param('id') id: string) {
    return this.bookingsService.refreshCompletionOtp(id);
  }

  @Patch(':id/confirm')
  async confirmBooking(@Param('id') id: string) {
    return this.bookingsService.updateStatus(id, BookingStatus.ACCEPTED);
  }

  @Patch(':id/accept')
  async acceptBooking(@Param('id') id: string, @Req() req) {
    const result = await this.bookingsService.acceptBooking(id, req.user.userId);

    // Send push notification to the customer via OneSignal
    const booking = result.booking;
    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Request Accepted!',
        body: `${booking.operator?.name || 'Your worker'} is on the way.`,
        data: { type: 'booking_accepted' },
      });
    }

    return result;
  }

  @Get(':id')
  async getBooking(@Param('id') id: string) {
    const booking = await this.bookingsService.getBookingById(id);
    if (!booking) throw new NotFoundException('Booking not found');
    return booking;
  }

  // Get booking status (for polling)
  @Get(':id/status')
  async getBookingStatus(@Param('id') id: string) {
    const booking = await this.bookingsService.getBookingById(id);
    if (!booking) throw new NotFoundException('Booking not found');
    return {
      status: booking.status,
      operatorName: booking.operator?.name,
      arrivalOtp: booking.status === BookingStatus.ACCEPTED ? booking.arrivalOtp : null,
    };
  }

  // DEFECT-012 FIX: Send arrival OTP to customer via FCM push
  @Patch(':id/arrive')
  async markArrived(@Param('id') id: string) {
    const booking = await this.bookingsService.getBookingById(id);
    if (!booking) throw new NotFoundException('Booking not found');

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
  async markComplete(@Param('id') id: string) {
    const booking = await this.bookingsService.getBookingById(id);
    if (!booking) throw new NotFoundException('Booking not found');

    const otp = booking.completionOtp;

    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Job marked as complete',
        body: `Completion OTP: ${otp}. Enter this to confirm and close the job.`,
      });
    }

    return { message: 'Completion OTP sent to customer.' };
  }

  @Post(':id/rating')
  async submitRating(@Param('id') id: string, @Body() body: { rating: number }) {
    return this.bookingsService.submitRating(id, body.rating);
  }
}
