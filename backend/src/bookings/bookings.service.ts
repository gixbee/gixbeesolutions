import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, In } from 'typeorm';
import { Booking, BookingStatus } from './booking.entity';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { BookingStatusService } from './booking-status.service';
import { BookingCancelService } from './booking-cancel.service';
import { BookingDispatchService } from './booking-dispatch.service';
import { BookingSettlementService } from './booking-settlement.service';
import { BookingProgressService } from './booking-progress.service';

@Injectable()
export class BookingsService {
  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    private dataSource: DataSource,
    private outboxService: OutboxService,
    private bookingStatusService: BookingStatusService,
    private bookingCancelService: BookingCancelService,
    private bookingDispatchService: BookingDispatchService,
    private bookingSettlementService: BookingSettlementService,
    private bookingProgressService: BookingProgressService,
  ) {}



  // ── Dispatch (delegates to BookingDispatchService) ─────────────────────

  createBooking(bookingData: Partial<Booking>): Promise<Booking> {
    return this.bookingDispatchService.createBooking(bookingData);
  }

  createBroadcastBooking(
    customerId: string,
    data: {
      skill: string;
      serviceLocation: string;
      serviceLat: number;
      serviceLng: number;
      amount: number;
      description?: string;
      preferredLanguages?: string[];
      addressId?: string;
      paymentMethod?: string;
      onSiteContact?: { name: string; relation: string; phone: string };
    },
  ) {
    return this.bookingDispatchService.createBroadcastBooking(customerId, data);
  }

  rebroadcastBooking(bookingId: string) {
    return this.bookingDispatchService.rebroadcastBooking(bookingId);
  }

  acceptBooking(bookingId: string, workerId: string) {
    return this.bookingDispatchService.acceptBooking(bookingId, workerId);
  }

  rejectBooking(bookingId: string, workerId: string) {
    return this.bookingDispatchService.rejectBooking(bookingId, workerId);
  }

  findPendingForWorker(workerId: string): Promise<Booking[]> {
    return this.bookingDispatchService.findPendingForWorker(workerId);
  }

  async updateStatus(
    id: string,
    status: BookingStatus,
  ): Promise<Booking | null> {
    const booking = await this.bookingsRepository.findOne({
      where: { id },
      relations: ['customer', 'operator'],
    });
    if (!booking) return null;

    const isTerminalCancel =
      status === BookingStatus.CANCELLED || status === BookingStatus.REJECTED;

    let outboxId: string | null = null;
    const saved = await this.dataSource.transaction(async (manager) => {
      booking.status = status;
      const updated = await manager.save(booking);

      if (isTerminalCancel) {
        const outbox = await this.outboxService.append(
          manager,
          OutboxEventType.BOOKING_CANCELLED,
          id,
          {
            bookingId: id,
            reason: 'status_update',
            // Timeout path (Bull requestTimeout) is the main CANCELLED caller here.
            source: status === BookingStatus.CANCELLED ? 'timeout' : 'system',
            operatorId: booking.operator?.id ?? null,
            operatorName: booking.operator?.name ?? null,
            customerId: booking.customer?.id ?? null,
          },
        );
        outboxId = outbox.id;
      }
      return updated;
    });

    if (outboxId) {
      await this.outboxService.enqueueDispatch(outboxId);
    } else {
      // Non-cancel status changes still warm the poll cache inline and emit socket event.
      await this.bookingStatusService.cacheAndEmitBookingStatus(id, {
        status: saved.status,
        operatorName: saved.operator?.name,
        operatorId: saved.operator?.id ?? null,
        customerId: saved.customer?.id ?? null,
        arrivalOtp:
          saved.status === BookingStatus.ACCEPTED ? saved.arrivalOtp : null,
      });
    }

    return saved;
  }

  // ── Customer Cancellation (with reason + refund) ──────────────────────────

  /**
   * Timeout auto-cancel — ATOMIC. The Bull requestTimeout job used to
   * check-then-act (read status, then blindly updateStatus), so an accept
   * committing in the gap was OVERWRITTEN to CANCELLED: the worker's fresh
   * job vanished from Home and the customer got a "No Workers Available"
   * push seconds after a pro accepted — both reported from the field
   * (acceptance at ~82s of the 90s window). Now the CANCELLED claim is a
   * single conditional UPDATE … WHERE status='REQUESTED' in the same
   * transaction as the outbox append: whichever of accept/timeout commits
   * first wins; the loser is a clean no-op.
   */
  // ── Cancel / late-cancel (delegates to BookingCancelService) ───────────

  timeoutCancelBooking(bookingId: string) {
    return this.bookingCancelService.timeoutCancelBooking(bookingId);
  }

  cancelBooking(
    id: string,
    reason: string,
    source: 'customer' | 'operator' = 'customer',
    opts?: {
      applyLateCancelStrike?: boolean;
      skipStageGate?: boolean;
      refundJobCredit?: boolean;
    },
  ) {
    return this.bookingCancelService.cancelBooking(id, reason, source, opts);
  }

  requestCancel(bookingId: string, customerUserId: string, reason?: string) {
    return this.bookingCancelService.requestCancel(
      bookingId,
      customerUserId,
      reason,
    );
  }

  approveCancelRequest(bookingId: string, operatorUserId: string) {
    return this.bookingCancelService.approveCancelRequest(
      bookingId,
      operatorUserId,
    );
  }

  declineCancelRequest(bookingId: string, operatorUserId: string) {
    return this.bookingCancelService.declineCancelRequest(
      bookingId,
      operatorUserId,
    );
  }

  withdrawCancelRequest(bookingId: string, customerUserId: string) {
    return this.bookingCancelService.withdrawCancelRequest(
      bookingId,
      customerUserId,
    );
  }

  markLateCancelCompensationPaid(customerUserId: string) {
    return this.bookingCancelService.markLateCancelCompensationPaid(
      customerUserId,
    );
  }

  getLateCancelCompensationQuote(userId: string) {
    return this.bookingCancelService.getLateCancelCompensationQuote(userId);
  }


  // ── Settlement (delegates to BookingSettlementService) ─────────────────

  verifyArrivalOtp(bookingId: string, otp: string) {
    return this.bookingSettlementService.verifyArrivalOtp(bookingId, otp);
  }

  verifyCompletionOtp(bookingId: string, otp: string) {
    return this.bookingSettlementService.verifyCompletionOtp(bookingId, otp);
  }

  markPaid(
    bookingId: string,
    userId: string,
    body: {
      collectionMethod?: string;
      honestyCheck?: string;
      safetyCheck?: string;
    } = {},
  ) {
    return this.bookingSettlementService.markPaid(bookingId, userId, body);
  }

  refreshCompletionOtp(bookingId: string) {
    return this.bookingSettlementService.refreshCompletionOtp(bookingId);
  }

  submitRating(bookingId: string, rating: number) {
    return this.bookingSettlementService.submitRating(bookingId, rating);
  }

  rateCustomer(bookingId: string, operatorUserId: string, rating: number) {
    return this.bookingSettlementService.rateCustomer(
      bookingId,
      operatorUserId,
      rating,
    );
  }

  reportDispute(bookingId: string, userId: string, reason: string) {
    return this.bookingSettlementService.reportDispute(
      bookingId,
      userId,
      reason,
    );
  }

  getDisputes(openOnly = false, page = 1, limit = 50) {
    return this.bookingSettlementService.getDisputes(openOnly, page, limit);
  }

  resolveDispute(bookingId: string, resolution: string) {
    return this.bookingSettlementService.resolveDispute(bookingId, resolution);
  }

  /** Facade — realtime status cache + socket emit. */
  cacheAndEmitBookingStatus(
    bookingId: string,
    payload: Record<string, any>,
  ): Promise<void> {
    return this.bookingStatusService.cacheAndEmitBookingStatus(
      bookingId,
      payload,
    );
  }
  /// Paginated all-bookings list for the portal monitor.
  async adminListBookings(
    status?: string,
    page = 1,
    limit = 50,
  ): Promise<Booking[]> {
    const where: any = {};
    if (status) {
      const statuses = status.split(',').map((s) => s.trim().toUpperCase());
      where.status = statuses.length === 1 ? statuses[0] : In(statuses);
    }
    return this.bookingsRepository.find({
      where,
      relations: ['customer', 'operator'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  getBookingById(id: string): Promise<Booking | null> {
    return this.bookingStatusService.getBookingById(id);
  }

  getStatusForParticipant(bookingId: string, userId: string) {
    return this.bookingStatusService.getStatusForParticipant(bookingId, userId);
  }

  /// SECURITY FIX: shared guard for the booking mutation endpoints that used  /// SECURITY FIX: shared guard for the booking mutation endpoints that used
  /// to trust the URL id. Throws unless the caller is this booking's customer
  /// or operator.
  async assertParticipant(bookingId: string, userId: string): Promise<Booking> {
    const booking = await this.getBookingById(bookingId);
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.customer?.id !== userId && booking.operator?.id !== userId) {
      throw new BadRequestException(
        'You are not a participant of this booking',
      );
    }
    return booking;
  }

  async findAllByUser(
    userId: string,
    role: 'customer' | 'operator',
    status?: string,
    page = 1,
    limit = 50,
  ): Promise<Booking[]> {
    const where: any =
      role === 'customer'
        ? { customer: { id: userId } }
        : { operator: { id: userId } };

    if (status) {
      const statuses = status.split(',').map((s) => s.trim().toUpperCase());
      where.status = statuses.length === 1 ? statuses[0] : In(statuses);
    }

    return this.bookingsRepository.find({
      where,
      relations: ['customer', 'operator'],
      // Same stable-pagination ordering as findMyBookings (tie-broken).
      order: { scheduledAt: 'DESC', createdAt: 'DESC', id: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  /// Single paginated list of bookings where the user is customer OR operator.
  /// Replaces the old two-query merge on GET /bookings/my (which doubled page
  /// size and could duplicate self-bookings if any slipped through).
  async findMyBookings(
    userId: string,
    status?: string,
    page = 1,
    limit = 50,
  ): Promise<Booking[]> {
    const qb = this.bookingsRepository
      .createQueryBuilder('booking')
      .leftJoinAndSelect('booking.customer', 'customer')
      .leftJoinAndSelect('booking.operator', 'operator')
      .where('(customer.id = :userId OR operator.id = :userId)', { userId })
      // PAGINATION FIX: scheduledAt alone is not a stable sort — instant
      // bookings share near-identical timestamps, and Postgres gives no
      // ordering guarantee among ties, so page 2 could repeat page-1 rows
      // and silently skip others ("my old bookings never show up").
      // NULLS LAST keeps rare schedule-less rows from jamming the top of
      // every page (DESC defaults to NULLS FIRST); createdAt + id break
      // ties deterministically.
      .orderBy('booking.scheduledAt', 'DESC', 'NULLS LAST')
      .addOrderBy('booking.createdAt', 'DESC')
      .addOrderBy('booking.id', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);

    if (status) {
      const statuses = status
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .filter(Boolean);
      if (statuses.length === 1) {
        qb.andWhere('booking.status = :status', { status: statuses[0] });
      } else if (statuses.length > 1) {
        qb.andWhere('booking.status IN (:...statuses)', { statuses });
      }
    }

    return qb.getMany();
  }

  // ── Progress / GPS (delegates to BookingProgressService) ───────────────

  evaluateWorkerProgress(
    booking: {
      serviceLat?: number | string | null;
      serviceLng?: number | string | null;
      acceptDistanceKm?: number | string | null;
    },
    location: { lat: number; lng: number; timestamp?: string } | null,
    nowMs: number = Date.now(),
  ) {
    return this.bookingProgressService.evaluateWorkerProgress(
      booking,
      location,
      nowMs,
    );
  }

  addGpsStrike(bookingId: string) {
    return this.bookingProgressService.addGpsStrike(bookingId);
  }

  calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
    return this.bookingProgressService.calculateDistance(
      lat1,
      lon1,
      lat2,
      lon2,
    );
  }

  /** Worker announces arrival — push arrival OTP to the customer. */
  notifyArrival(bookingId: string, workerId: string) {
    return this.bookingSettlementService.notifyArrival(bookingId, workerId);
  }

  /** Worker marks complete — push completion OTP to the customer. */
  notifyCompletion(bookingId: string, workerId: string) {
    return this.bookingSettlementService.notifyCompletion(bookingId, workerId);
  }
}
