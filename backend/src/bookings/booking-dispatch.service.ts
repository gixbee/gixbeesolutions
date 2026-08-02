import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bull';
import { InjectRepository } from '@nestjs/typeorm';
import type { Queue } from 'bull';
import { DataSource, In, Repository } from 'typeorm';
import { DEFAULT_BOOKING_PAYMENT_METHOD } from '../common/money-model';
import { MessagesGateway } from '../messages/messages.gateway';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { User } from '../users/user.entity';
import {
  BookingBroadcastService,
  CreateBroadcastBookingData,
} from './booking-broadcast.service';
import { BookingClaimService } from './booking-claim.service';
import { Booking, BookingStatus } from './booking.entity';
import { BookingStatusService } from './booking-status.service';

@Injectable()
export class BookingDispatchService {
  constructor(
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    @InjectQueue('bookings') private readonly bookingsQueue: Queue,
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
    private readonly dataSource: DataSource,
    private readonly messagesGateway: MessagesGateway,
    private readonly bookingStatusService: BookingStatusService,
    private readonly bookingClaimService: BookingClaimService,
    private readonly bookingBroadcastService: BookingBroadcastService,
  ) {}

  private generateOtp(): string {
    return Math.floor(1000 + Math.random() * 9000).toString();
  }

  async createBooking(bookingData: Partial<Booking>): Promise<Booking> {
    const customerId =
      (bookingData.customer as any)?.id ?? bookingData.customer;
    const operatorId =
      (bookingData.operator as any)?.id ?? bookingData.operator;

    if (customerId) {
      await this.assertInstantHelpAllowed(String(customerId));
    }

    if (customerId && operatorId && customerId === operatorId) {
      throw new BadRequestException('You cannot book yourself.');
    }

    if (operatorId) {
      const activeJob = await this.bookingsRepository.findOne({
        where: [
          { operator: { id: operatorId }, status: BookingStatus.ACCEPTED },
          { operator: { id: operatorId }, status: BookingStatus.ARRIVED },
          { operator: { id: operatorId }, status: BookingStatus.ACTIVE },
          { operator: { id: operatorId }, status: BookingStatus.CONFIRMED },
        ],
      });
      if (activeJob) {
        throw new BadRequestException(
          'This worker is currently on an active job. Try again later.',
        );
      }
    }

    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();
    const booking = this.bookingsRepository.create({
      ...bookingData,
      paymentMethod:
        bookingData.paymentMethod || DEFAULT_BOOKING_PAYMENT_METHOD,
      status: BookingStatus.REQUESTED,
      arrivalOtp,
      completionOtp,
    });
    const savedBooking = await this.bookingsRepository.save(booking);

    await this.redisService.saveOtp(
      `otp:booking:${savedBooking.id}:arrival`,
      arrivalOtp,
    );
    await this.redisService.saveOtp(
      `otp:booking:${savedBooking.id}:completion`,
      completionOtp,
    );
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: savedBooking.id, attempt: 1 },
      {
        jobId: `requestTimeout:${savedBooking.id}`,
        delay: 90 * 1000,
        removeOnComplete: true,
      },
    );

    if (operatorId) {
      await this.redisService.addPendingBooking(operatorId, savedBooking.id);
      await this.notificationsService.notifyWorkerNewBooking(
        operatorId,
        savedBooking.id,
        (bookingData as any).skill ?? 'General Help',
      );
      try {
        this.messagesGateway.emitUserEvent(operatorId, 'new_booking_request', {
          id: savedBooking.id,
          skill: (bookingData as any).skill ?? 'General Help',
          serviceLocation: savedBooking.serviceLocation,
          serviceLat: savedBooking.serviceLat ?? null,
          serviceLng: savedBooking.serviceLng ?? null,
          amount: savedBooking.amount,
          customer_name: savedBooking.customer?.name ?? 'Customer',
          createdAt: savedBooking.createdAt
            ? new Date(savedBooking.createdAt).toISOString()
            : new Date().toISOString(),
        });
      } catch (error) {
        console.error('[CreateBooking] socket emit failed:', error);
      }
    }

    await this.bookingStatusService.cacheAndEmitBookingStatus(savedBooking.id, {
      status: 'REQUESTED',
      operatorName: null,
      operatorId: operatorId ?? null,
      customerId: customerId ?? null,
      arrivalOtp: savedBooking.arrivalOtp,
    });
    return savedBooking;
  }

  async createBroadcastBooking(
    customerId: string,
    data: CreateBroadcastBookingData,
  ): Promise<{ booking: Booking; notified: number }> {
    await this.assertInstantHelpAllowed(customerId);
    return this.bookingBroadcastService.createBroadcastBooking(
      customerId,
      data,
    );
  }

  acceptBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string; status: string; booking: any }> {
    return this.bookingClaimService.acceptBooking(bookingId, workerId);
  }

  rejectBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string }> {
    return this.bookingClaimService.rejectBooking(bookingId, workerId);
  }

  rebroadcastBooking(
    bookingId: string,
  ): Promise<{ stillOpen: boolean; notified: number }> {
    return this.bookingBroadcastService.rebroadcastBooking(bookingId);
  }

  private async assertInstantHelpAllowed(customerId: string): Promise<void> {
    const user = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: customerId } });
    if (user?.instantHelpBlocked) {
      const amount = user.unblockCompensationAmountInr ?? 0;
      const distanceKm = user.unblockCompensationDistanceKm;
      const distanceText =
        distanceKm != null && Number(distanceKm) > 0
          ? ` (${Number(distanceKm).toFixed(1)} km travel)`
          : '';
      throw new BadRequestException(
        `Instant Help is blocked after repeated late cancels. Pay ₹${amount} travel compensation${distanceText} to unlock.`,
      );
    }
  }

  async findPendingForWorker(workerId: string): Promise<Booking[]> {
    const ids = await this.redisService.getPendingBookingIds(workerId);
    if (ids.length > 0) {
      const bookings = await this.bookingsRepository.find({
        where: { id: In(ids) },
        relations: ['customer', 'operator'],
      });
      const open = bookings.filter(
        (booking) => booking.status === BookingStatus.REQUESTED,
      );
      for (const stale of bookings.filter(
        (booking) => booking.status !== BookingStatus.REQUESTED,
      )) {
        await this.redisService
          .removePendingBooking(workerId, stale.id)
          .catch(() => {});
      }
      return open.sort((a, b) => ids.indexOf(a.id) - ids.indexOf(b.id));
    }

    const dbBookings = await this.bookingsRepository.find({
      where: { operator: { id: workerId }, status: BookingStatus.REQUESTED },
      relations: ['customer', 'operator'],
      order: { createdAt: 'DESC' },
    });
    for (const booking of dbBookings) {
      await this.redisService.addPendingBooking(workerId, booking.id);
    }
    return dbBookings;
  }
}
