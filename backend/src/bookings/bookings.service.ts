import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, In } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { Booking, BookingStatus, BookingType } from './booking.entity';
import { WalletsService } from '../wallets/wallets.service';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { WorkersService } from '../workers/workers.service';

@Injectable()
export class BookingsService {
  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    @InjectRepository(WorkerProfile)
    private workerProfileRepo: Repository<WorkerProfile>,
    @InjectQueue('bookings') private bookingsQueue: Queue,
    private walletsService: WalletsService,
    private notificationsService: NotificationsService,
    private redisService: RedisService,
    private workersService: WorkersService,
    private dataSource: DataSource,
  ) {}

  private generateOtp(): string {
    return Math.floor(1000 + Math.random() * 9000).toString();
  }

  // ── Create Booking ────────────────────────────────────────────────────────

  /**
   * Creates a booking request for a specific worker.
   *
   * Race condition handling:
   *   Multiple customers can book the same worker simultaneously. Each booking
   *   is created as REQUESTED. When the worker accepts ONE, all other REQUESTED
   *   bookings for that worker are auto-cancelled (see acceptBooking).
   *
   *   We only hard-block if the worker is ALREADY on an active/accepted job.
   *   This allows the worker to see a queue of incoming requests and pick the
   *   best one, rather than rejecting all but the first.
   */
  async createBooking(bookingData: Partial<Booking>): Promise<Booking> {
    const customerId = (bookingData.customer as any)?.id ?? bookingData.customer;
    const operatorId = (bookingData.operator as any)?.id ?? bookingData.operator;

    // Prevent self-booking
    if (customerId && operatorId && customerId === operatorId) {
      throw new BadRequestException('You cannot book yourself.');
    }

    // Prevent booking a worker who is already mid-job (ACTIVE or ARRIVED)
    if (operatorId) {
      const activeJob = await this.bookingsRepository.findOne({
        where: [
          { operator: { id: operatorId }, status: BookingStatus.ACTIVE },
          { operator: { id: operatorId }, status: BookingStatus.ARRIVED },
        ],
      });
      if (activeJob) {
        throw new BadRequestException(
          'This worker is currently on an active job. Try again later.',
        );
      }
    }

    // Generate OTPs at booking creation time
    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();

    const booking = this.bookingsRepository.create({
      ...bookingData,
      status: BookingStatus.REQUESTED,
      arrivalOtp,
      completionOtp,
    });
    const savedBooking = await this.bookingsRepository.save(booking);

    // Save OTPs to Redis (24-hour TTL)
    await this.redisService.saveOtp(
      `otp:booking:${savedBooking.id}:arrival`,
      arrivalOtp,
    );
    await this.redisService.saveOtp(
      `otp:booking:${savedBooking.id}:completion`,
      completionOtp,
    );

    // Schedule 90-second request timeout
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: savedBooking.id },
      { delay: 90 * 1000 },
    );

    // Add to Redis pending list for fast poll discovery
    if (operatorId) {
      await this.redisService.addPendingBooking(operatorId, savedBooking.id);
    }

    // Push notification to worker
    if (operatorId) {
      await this.notificationsService.notifyWorkerNewBooking(
        operatorId,
        savedBooking.id,
        (bookingData as any).skill ?? 'General Help',
      );
    }

    // Cache initial status for poll endpoint
    await this.redisService.cacheBookingStatus(savedBooking.id, {
      status: 'REQUESTED',
      operatorName: null,
    });

    return savedBooking;
  }

  // ── Accept Booking ────────────────────────────────────────────────────────

  /**
   * Worker accepts one booking from their queue.
   *
   * When accepted:
   *   1. This booking → ACCEPTED
   *   2. All OTHER pending REQUESTED bookings for this worker → CANCELLED
   *   3. Each cancelled customer receives a push notification
   *   4. Worker wallet is debited the platform fee
   *   5. Worker status → busy
   *
   * This ensures the worker only ever has one active job at a time,
   * while allowing multiple customers to queue up for the same worker.
   */
  /**
   * v126 broadcast dispatch ("first accept wins"): creates ONE booking with
   * NO pre-assigned worker, then notifies every eligible nearby LIVE pro for
   * the skill (Redis skill index + GEO search via WorkersService.getNearby).
   * Each notified worker sees it in their pending queue; acceptBooking's row
   * lock makes the claim atomic. The existing 90s requestTimeout cancels the
   * request if nobody accepts. Returns how many pros were notified so the
   * client can short-circuit to the no-workers screen when it's zero.
   */
  async createBroadcastBooking(
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
  ): Promise<{ booking: Booking; notified: number }> {
    // Find eligible pros FIRST — no point persisting a request nobody can see.
    const nearby = await this.workersService.getNearby(
      customerId,
      data.skill,
      data.serviceLat,
      data.serviceLng,
    );

    // v126 language matching: when the customer requires languages, notify
    // only pros with an overlap. Pros who haven't set their languages yet
    // (null/empty) are INCLUDED — lenient by design so legacy profiles keep
    // receiving jobs until they fill it in via Go Live.
    const wanted = (data.preferredLanguages ?? []).map((l) => l.toLowerCase());
    const languageEligible =
      wanted.length === 0
        ? nearby
        : nearby.filter((w) => {
            const spoken = (w.languages ?? []).map((l) => l.toLowerCase());
            return spoken.length === 0 || spoken.some((l) => wanted.includes(l));
          });

    // Cap the fan-out; getNearby is rating-sorted, so the best pros hear first.
    const targets = languageEligible.slice(0, 15);

    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();

    const booking = this.bookingsRepository.create({
      customer: { id: customerId } as any,
      operator: null as any,
      skill: data.skill,
      serviceLocation: data.serviceLocation,
      serviceLat: data.serviceLat,
      serviceLng: data.serviceLng,
      addressId: data.addressId,
      description: data.description,
      preferredLanguages: data.preferredLanguages,
      onSiteContact: data.onSiteContact,
      scheduledAt: new Date(),
      amount: data.amount,
      type: BookingType.INSTANT,
      paymentMethod: data.paymentMethod || 'WALLET',
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

    // Same 90-second timeout as targeted requests.
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: savedBooking.id },
      { delay: 90 * 1000 },
    );

    await this.redisService.cacheBookingStatus(savedBooking.id, {
      status: 'REQUESTED',
      operatorName: null,
    });

    // Fan out: pending-queue entry + one multicast push. AUDIT FIX: was a
    // serial await sendToUser loop (≤15); Redis pending is parallelized and
    // FCM goes through sendToUsers (sendEachForMulticast).
    const notifiedIds: string[] = [];
    await Promise.all(
      targets.map(async (w) => {
        try {
          await this.redisService.addPendingBooking(w.id, savedBooking.id);
          notifiedIds.push(w.id);
        } catch (e) {
          console.error(`[BroadcastBooking] pending ${w.id} failed:`, e);
        }
      }),
    );
    if (notifiedIds.length > 0) {
      await this.notificationsService
        .sendToUsers(notifiedIds, {
          title: 'New Job Request',
          body: `A customer needs ${data.skill} help nearby.`,
          data: { type: 'new_booking', bookingId: savedBooking.id },
        })
        .catch((e) =>
          console.error('[BroadcastBooking] multicast failed:', e),
        );
      await this.redisService.set(
        `booking:notified:${savedBooking.id}`,
        JSON.stringify(notifiedIds),
        60 * 60,
      );
    }

    console.log(
      `[BroadcastBooking] ${savedBooking.id} broadcast to ${notifiedIds.length} pros for ${data.skill}`,
    );
    return { booking: savedBooking, notified: notifiedIds.length };
  }

  async acceptBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string; status: string; booking: any }> {
    console.log(`[AcceptBooking] START — bookingId=${bookingId}, workerId=${workerId}`);

    // ── STEP 1: Database transaction (only DB writes that MUST be atomic) ──
    let savedBooking: Booking;
    let otherPendingFiltered: Booking[] = [];
    let operatorName: string | null = null;

    try {
      const txResult = await this.dataSource.transaction(async (manager) => {
        console.log('[AcceptBooking] Inside transaction — locking booking row');

        // Step 1: Lock ONLY the booking row (no joins — PostgreSQL doesn't support FOR UPDATE with LEFT JOIN)
        const lockedBooking = await manager
          .createQueryBuilder(Booking, 'booking')
          .setLock('pessimistic_write')
          .where('booking.id = :bookingId', { bookingId })
          .getOne();

        if (!lockedBooking) throw new NotFoundException('Booking not found');
        console.log(`[AcceptBooking] Locked booking — status=${lockedBooking.status}`);

        if (lockedBooking.status !== BookingStatus.REQUESTED) {
          throw new BadRequestException(
            'This booking is no longer available — it may have been accepted or cancelled.',
          );
        }

        // Step 2: Now load the full booking WITH relations (no lock needed, row is already locked)
        const booking = await manager.findOne(Booking, {
          where: { id: bookingId },
          relations: ['customer', 'operator'],
        });

        if (!booking) throw new NotFoundException('Booking not found');
        console.log(`[AcceptBooking] Booking loaded — operator=${booking.operator?.id}`);

        if (!booking.operator) {
          // Broadcast request (v126 first-accept-wins): no worker was
          // pre-assigned. The pessimistic row lock above makes this claim
          // atomic — the first accepter flips REQUESTED→ACCEPTED and later
          // accepters fail the REQUESTED check with a clean 400.
          booking.operator = { id: workerId } as any;
          console.log(`[AcceptBooking] Broadcast claim by worker ${workerId}`);
        } else if (booking.operator.id !== workerId) {
          throw new BadRequestException('You are not assigned to this booking.');
        }

        // Transition this booking → ACCEPTED
        booking.status = BookingStatus.ACCEPTED;
        await manager.save(booking);
        // Reload with relations so a broadcast claim resolves the operator's
        // name (the claim above only set the id).
        const saved =
          (await manager.findOne(Booking, {
            where: { id: bookingId },
            relations: ['customer', 'operator'],
          })) ?? booking;
        console.log('[AcceptBooking] Booking saved as ACCEPTED');

        // Find other REQUESTED bookings for this worker
        const otherPending = await manager.find(Booking, {
          where: {
            operator: { id: workerId },
            status: BookingStatus.REQUESTED,
          },
          relations: ['customer'],
        });

        const filtered = otherPending.filter((b) => b.id !== bookingId);

        if (filtered.length > 0) {
          console.log(`[AcceptBooking] Cancelling ${filtered.length} other pending bookings`);
          await manager.update(
            Booking,
            { id: In(filtered.map((b) => b.id)) },
            { status: BookingStatus.CANCELLED },
          );
        }

        return {
          saved,
          filtered,
          opName: saved.operator?.name ?? null,
          customerId: saved.customer?.id ?? null,
        };
      });

      savedBooking = txResult.saved;
      otherPendingFiltered = txResult.filtered;
      operatorName = txResult.opName;
      console.log('[AcceptBooking] Transaction committed successfully');
    } catch (error) {
      console.error('[AcceptBooking] Transaction FAILED:', error?.message ?? error);
      throw error;
    }

    // ── STEP 2: Side effects OUTSIDE the transaction (non-atomic, resilient) ──

    // Deduct platform fee from worker wallet
    try {
      console.log('[AcceptBooking] Deducting booking fee...');
      await this.walletsService.deductBookingFee(workerId);
      console.log('[AcceptBooking] Booking fee deducted');
    } catch (error) {
      // Log but don't fail the accept — fee can be reconciled later
      console.error('[AcceptBooking] Wallet deduction failed (non-fatal):', error?.message ?? error);
    }

    // Mark worker as busy in Redis
    try {
      await this.workersService.setWorkerStatus(workerId, 'busy');
    } catch (e) {
      console.error('[AcceptBooking] setWorkerStatus failed:', e);
    }

    // Remove from Redis pending list
    try {
      await this.redisService.removePendingBooking(workerId, bookingId);
    } catch (e) {
      console.error('[AcceptBooking] removePendingBooking failed:', e);
    }

    // Cache ACCEPTED status for poll endpoint. operatorId included so the
    // customer app can identify a broadcast-claimed worker it never picked.
    try {
      await this.redisService.cacheBookingStatus(bookingId, {
        status: 'ACCEPTED',
        operatorName: operatorName,
        operatorId: workerId,
        arrivalOtp: savedBooking.arrivalOtp,
      });
    } catch (e) {
      console.error('[AcceptBooking] cacheBookingStatus failed:', e);
    }

    // Broadcast cleanup: pull this request out of every OTHER notified
    // worker's pending list so it disappears from their queues.
    try {
      const raw = await this.redisService.get(`booking:notified:${bookingId}`);
      if (raw) {
        const notified: string[] = JSON.parse(raw);
        await Promise.all(
          notified
            .filter((otherId) => otherId !== workerId)
            .map((otherId) =>
              this.redisService
                .removePendingBooking(otherId, bookingId)
                .catch(() => {}),
            ),
        );
        await this.redisService.del(`booking:notified:${bookingId}`);
      }
    } catch (e) {
      console.error('[AcceptBooking] broadcast cleanup failed:', e);
    }

    // Notify cancelled customers (AUDIT FIX: one multicast, not serial awaits).
    const cancelledCustomerIds = otherPendingFiltered
      .map((c) => c.customer?.id)
      .filter((id): id is string => !!id);
    if (cancelledCustomerIds.length > 0) {
      await this.notificationsService
        .sendToUsers(cancelledCustomerIds, {
          title: 'Booking Cancelled',
          body: 'The worker accepted another job. Please try booking again.',
          data: { type: 'booking_cancelled' },
        })
        .catch((e) =>
          console.error('[AcceptBooking] cancel multicast failed:', e),
        );
    }
    await Promise.all(
      otherPendingFiltered.map(async (cancelled) => {
        try {
          await this.redisService
            .removePendingBooking(workerId, cancelled.id)
            .catch(() => {});
          await this.redisService.cacheBookingStatus(cancelled.id, {
            status: 'CANCELLED',
            operatorName: null,
          });
        } catch (e) {
          console.error(
            `[AcceptBooking] Cancelled-cache failed for ${cancelled.id}:`,
            e,
          );
        }
      }),
    );

    // Schedule GPS monitoring jobs
    try {
      await this.bookingsQueue.add(
        'sevenMinuteReminder',
        { bookingId: savedBooking.id },
        { delay: 7 * 60 * 1000 },
      );
      await this.bookingsQueue.add(
        'tenMinuteGpsCheck',
        { bookingId: savedBooking.id },
        { delay: 10 * 60 * 1000 },
      );
    } catch (e) {
      console.error('[AcceptBooking] Queue scheduling failed:', e);
    }

    console.log('[AcceptBooking] DONE — returning success');

    // Return a plain object (no circular entity references)
    return {
      message: `Booking accepted. Head to the service location now.`,
      status: 'ACCEPTED',
      booking: {
        id: savedBooking.id,
        status: savedBooking.status,
        skill: savedBooking.skill,
        amount: savedBooking.amount,
        serviceLocation: savedBooking.serviceLocation,
        arrivalOtp: savedBooking.arrivalOtp,
        completionOtp: savedBooking.completionOtp,
        createdAt: savedBooking.createdAt,
      },
    };
  }

  // ── Reject / Decline Booking ──────────────────────────────────────────────

  /**
   * Worker explicitly declines one booking from their queue.
   * The customer is notified and may rebook with a different worker.
   * Other pending bookings in the worker's queue are unaffected.
   */
  async rejectBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId, operator: { id: workerId } },
      relations: ['customer'],
    });

    if (!booking) throw new NotFoundException('Booking not found');

    if (booking.status !== BookingStatus.REQUESTED) {
      throw new BadRequestException('Only pending requests can be declined.');
    }

    booking.status = BookingStatus.REJECTED;
    await this.bookingsRepository.save(booking);

    await this.redisService.removePendingBooking(workerId, bookingId);
    await this.redisService.cacheBookingStatus(bookingId, {
      status: 'REJECTED',
      operatorName: null,
    });

    if (booking.customer?.id) {
      await this.notificationsService.notifyBookingCancelled(
        booking.customer.id,
        'The worker is unavailable for this request. Please try again.',
      );
    }

    return { message: 'Booking declined.' };
  }

  // ── Update Status ─────────────────────────────────────────────────────────

  async updateStatus(id: string, status: BookingStatus): Promise<Booking | null> {
    const booking = await this.bookingsRepository.findOne({
      where: { id },
      relations: ['operator'],
    });
    if (!booking) return null;

    booking.status = status;
    const saved = await this.bookingsRepository.save(booking);

    await this.redisService.cacheBookingStatus(id, {
      status: saved.status,
      operatorName: saved.operator?.name,
      arrivalOtp:
        saved.status === BookingStatus.ACCEPTED ? saved.arrivalOtp : null,
    });

    if (
      status === BookingStatus.CANCELLED ||
      status === BookingStatus.REJECTED
    ) {
      if (booking.operator?.id) {
        await this.redisService.removePendingBooking(booking.operator.id, id);
      }
    }

    return saved;
  }

  // ── Customer Cancellation (with reason + refund) ──────────────────────────

  /**
   * Cancels a booking, records the reason, and refunds any captured payment
   * back to the customer's wallet. Completed bookings cannot be cancelled.
   */
  async cancelBooking(
    id: string,
    reason: string,
  ): Promise<{
    status: string;
    refundAmount: number;
    refundMethod: string;
    message: string;
  }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.status === BookingStatus.COMPLETED) {
      throw new BadRequestException('Completed bookings cannot be cancelled.');
    }

    booking.status = BookingStatus.CANCELLED;
    booking.cancellationReason = reason;

    // Refund policy: refund only money Gixbee actually captured.
    // - WALLET bookings: settlement moved funds customer→worker, so the
    //   cancellation reverses that pair (worker debit + customer credit —
    //   the clawback that was previously missing).
    // - CASH/UPI direct collection (markPaid): the worker was paid
    //   directly and Gixbee never held the money — no wallet credit is
    //   minted out of thin air; the parties settle directly.
    // - Unpaid bookings: nothing captured, nothing to refund.
    let refundAmount = 0;
    let refundMethod = 'NONE';
    if (booking.isPaid && booking.customer?.id) {
      const paidAmount = Number(booking.totalAmount ?? booking.amount) || 0;
      if (paidAmount > 0) {
        if (booking.paymentMethod === 'WALLET' && booking.operator?.id) {
          await this.walletsService.reverseBookingTransfer(
            booking.customer.id,
            booking.operator.id,
            paidAmount,
            id,
          );
          refundAmount = paidAmount;
          refundMethod = 'WALLET';
        } else {
          refundMethod = 'DIRECT';
        }
      }
    }

    await this.bookingsRepository.save(booking);

    if (booking.operator?.id) {
      await this.redisService
        .removePendingBooking(booking.operator.id, id)
        .catch(() => {});
      // Let the worker know the job was cancelled.
      await this.notificationsService
        .sendToUser(booking.operator.id, {
          title: 'Booking cancelled',
          body: `A customer cancelled their booking.`,
          data: { type: 'booking_cancelled', bookingId: id },
        })
        .catch(() => {});
    }
    await this.redisService
      .cacheBookingStatus(id, {
        status: 'CANCELLED',
        operatorName: booking.operator?.name,
        arrivalOtp: null,
      })
      .catch(() => {});

    return {
      status: 'CANCELLED',
      refundAmount,
      refundMethod,
      message:
        refundMethod === 'DIRECT'
          ? 'Booking cancelled. Payment was collected directly by the worker — please settle any refund with them.'
          : 'Booking cancelled',
    };
  }

  // ── Find Pending for Worker ───────────────────────────────────────────────

  /**
   * Returns ALL pending booking requests for this worker.
   * Used by the worker's queue UI to show multiple simultaneous requests.
   */
  async findPendingForWorker(workerId: string): Promise<Booking[]> {
    const ids = await this.redisService.getPendingBookingIds(workerId);

    if (ids.length > 0) {
      const bookings = await this.bookingsRepository.find({
        where: { id: In(ids) },
        relations: ['customer', 'operator'],
      });
      // Drop entries that are no longer open — e.g. a broadcast request
      // another pro already claimed, or a timed-out request — and prune the
      // stale ids from this worker's Redis queue.
      const open = bookings.filter((b) => b.status === BookingStatus.REQUESTED);
      for (const stale of bookings.filter((b) => b.status !== BookingStatus.REQUESTED)) {
        await this.redisService.removePendingBooking(workerId, stale.id).catch(() => {});
      }
      return open.sort((a, b) => ids.indexOf(a.id) - ids.indexOf(b.id));
    }

    const dbBookings = await this.bookingsRepository.find({
      where: { operator: { id: workerId }, status: BookingStatus.REQUESTED },
      relations: ['customer', 'operator'],
      order: { createdAt: 'DESC' },
    });

    if (dbBookings.length > 0) {
      for (const b of dbBookings) {
        await this.redisService.addPendingBooking(workerId, b.id);
      }
    }

    return dbBookings;
  }

  // ── OTP Verification ──────────────────────────────────────────────────────

  async verifyArrivalOtp(
    bookingId: string,
    otp: string,
  ): Promise<{ message: string; status: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.arrivalOtp || booking.arrivalOtp !== otp) {
      throw new BadRequestException('Invalid arrival OTP');
    }

    this.redisService.deleteOtp(`otp:booking:${bookingId}:arrival`).catch(() => {});

    booking.status = BookingStatus.ACTIVE;
    booking.startedAt = new Date();
    await this.bookingsRepository.save(booking);

    await this.redisService.cacheBookingStatus(bookingId, {
      status: 'ACTIVE',
      operatorName: null,
    });

    return { message: 'Arrival confirmed. Job is now active.', status: 'ACTIVE' };
  }

  async verifyCompletionOtp(
    bookingId: string,
    otp: string,
  ): Promise<{ message: string; status: string; billingHours: number; paymentMethod: string; totalAmount: number; isPaid: boolean; }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.completionOtp || booking.completionOtp !== otp) {
      throw new BadRequestException('Invalid completion OTP');
    }

    this.redisService.deleteOtp(`otp:booking:${bookingId}:completion`).catch(() => {});

    if (booking.status !== BookingStatus.ACTIVE) {
      throw new BadRequestException('Job must be active to complete');
    }

    // AUDIT FIX (double-settlement race): atomically claim the completion.
    // Only ONE concurrent verify call can flip ACTIVE → COMPLETED; losers
    // fail here BEFORE any wallet settlement can run twice.
    const claim = await this.bookingsRepository.update(
      { id: bookingId, status: BookingStatus.ACTIVE },
      { status: BookingStatus.COMPLETED, completedAt: new Date() },
    );
    if (!claim.affected) {
      throw new BadRequestException('Job must be active to complete');
    }

    const startTime = booking.startedAt
      ? new Date(booking.startedAt).getTime()
      : Date.now();
    // Bill only WORKED time: subtract approved pause windows (pausedMinutes),
    // including a still-open pause at completion time.
    let pausedMs = (booking.pausedMinutes ?? 0) * 60 * 1000;
    if (booking.pausedAt) {
      pausedMs += Math.max(0, Date.now() - new Date(booking.pausedAt).getTime());
      booking.pausedAt = null as any;
    }
    const workedMs = Math.max(0, Date.now() - startTime - pausedMs);
    const hoursWorked = Math.max(1, Math.ceil(workedMs / (1000 * 60 * 60)));

    booking.status = BookingStatus.COMPLETED; // already claimed atomically above
    booking.completedAt = booking.completedAt ?? new Date();
    booking.billingHours = hoursWorked;
    // INSTANT (broadcast) requests carry the customer's ₹/hr budget in
    // `amount` — total = rate × worked hours. PACKAGE/CUSTOM/RENTAL keep
    // `amount` as the flat agreed price from the rate chart / quote.
    const totalAmount =
      booking.type === BookingType.INSTANT
        ? (booking.amount || 0) * hoursWorked
        : booking.amount || 0;
    booking.totalAmount = totalAmount;

    // Settle WALLET payments for real: debit customer, credit worker (atomic).
    // On insufficient balance the booking stays unpaid and the worker's
    // collect-payment flow (cash/UPI → markPaid) takes over.
    if (booking.paymentMethod === 'WALLET') {
      if (totalAmount <= 0) {
        booking.isPaid = true; // nothing to settle
      } else if (booking.customer?.id && booking.operator?.id) {
        try {
          await this.walletsService.transferForBooking(
            booking.customer.id,
            booking.operator.id,
            totalAmount,
            bookingId,
          );
          booking.isPaid = true;
          console.log(
            `[CompleteBooking] Wallet settled: ₹${totalAmount} customer→worker for ${bookingId}`,
          );
        } catch (error) {
          booking.isPaid = false;
          console.error(
            '[CompleteBooking] Wallet settlement failed — falling back to direct collection:',
            error?.message ?? error,
          );
        }
      }
    }

    await this.bookingsRepository.save(booking);

    // Update Redis cache
    await this.redisService.cacheBookingStatus(bookingId, {
      status: 'COMPLETED',
      operatorName: booking.operator?.name,
    });

    // Release worker and handle first-job bonus
    if (booking.operator?.id) {
      await this.workersService.setWorkerStatus(booking.operator.id, 'available');

      const workerProfile = await this.workerProfileRepo.findOne({
        where: { user: { id: booking.operator.id } },
      });
      if (workerProfile && !workerProfile.isFirstJobDone) {
        await this.walletsService.addFunds(booking.operator.id, 12);
        workerProfile.isFirstJobDone = true;
        await this.workerProfileRepo.save(workerProfile);
      }
    }

    return {
      message: 'Job completed successfully.',
      status: 'COMPLETED',
      billingHours: hoursWorked,
      paymentMethod: booking.paymentMethod,
      totalAmount,
      isPaid: booking.isPaid,
    };
  }

  // AUDIT FIX: was callable by ANY authenticated user on ANY booking. Only
  // the booking's participants may mark it paid, and only after completion.
  async markPaid(bookingId: string, userId: string): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== userId && booking.customer?.id !== userId) {
      throw new BadRequestException('Only participants of this booking can mark it paid');
    }
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestException('Only completed bookings can be marked paid');
    }

    booking.isPaid = true;
    await this.bookingsRepository.save(booking);

    return { message: 'Booking marked as paid.' };
  }

  async refreshCompletionOtp(
    bookingId: string,
  ): Promise<{ message: string; completionOtp: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    const newOtp = this.generateOtp();
    booking.completionOtp = newOtp;
    await this.bookingsRepository.save(booking);
    await this.redisService.saveOtp(`otp:booking:${bookingId}:completion`, newOtp);

    if (booking.customer?.id) {
      await this.notificationsService.notifyCustomerJobComplete(
        booking.customer.id,
        newOtp,
      );
    }

    return { message: 'Completion OTP refreshed', completionOtp: newOtp };
  }

  /**
   * Customer rates the worker after COMPLETED.
   * AUDIT FIX: booking + worker-profile updates run in one transaction with
   * pessimistic locks so concurrent ratings cannot both read the same
   * (rating, reviewCount) and drop one from the average. Re-rating an already
   * rated booking is idempotent (no second fold into the average).
   */
  async submitRating(
    bookingId: string,
    rating: number,
  ): Promise<{ message: string }> {
    await this.dataSource.transaction(async (manager) => {
      const bookingRepo = manager.getRepository(Booking);
      const profileRepo = manager.getRepository(WorkerProfile);

      const locked = await bookingRepo
        .createQueryBuilder('booking')
        .setLock('pessimistic_write')
        .where('booking.id = :bookingId', { bookingId })
        .getOne();
      if (!locked) throw new NotFoundException('Booking not found');

      const booking = await bookingRepo.findOne({
        where: { id: bookingId },
        relations: ['operator'],
      });
      if (!booking) throw new NotFoundException('Booking not found');
      if (booking.status !== BookingStatus.COMPLETED) {
        throw new BadRequestException('Can only rate completed jobs');
      }
      if (booking.rating != null) {
        return; // already counted — don't inflate reviewCount
      }

      booking.rating = rating;
      await bookingRepo.save(booking);

      if (!booking.operator?.id) return;

      const profile = await profileRepo.findOne({
        where: { user: { id: booking.operator.id } },
      });
      if (!profile) return;

      await profileRepo
        .createQueryBuilder('profile')
        .setLock('pessimistic_write')
        .where('profile.id = :id', { id: profile.id })
        .getOne();

      const fresh = await profileRepo.findOne({ where: { id: profile.id } });
      if (!fresh) return;

      const currentTotal = Number(fresh.rating) * fresh.reviewCount;
      fresh.reviewCount += 1;
      fresh.rating = (currentTotal + rating) / fresh.reviewCount;
      await profileRepo.save(fresh);
    });

    return { message: 'Rating submitted successfully' };
  }

  // ── v126 parity: worker rates the customer after completion. Mirrors
  // submitRating but writes customerRating and checks the caller IS the
  // operator on this booking.
  async rateCustomer(
    bookingId: string,
    operatorUserId: string,
    rating: number,
  ): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== operatorUserId) {
      throw new BadRequestException('Only the assigned worker can rate this customer');
    }
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestException('Can only rate completed jobs');
    }
    booking.customerRating = rating;
    await this.bookingsRepository.save(booking);
    return { message: 'Customer rating submitted' };
  }

  // ── Pause / resume (v126 Instant Help c12–c14 / w6–w7) ────────────────────
  // Worker requests a pause mid-job → customer approves (timer stops) or
  // declines → worker resumes when work restarts. Status stays ACTIVE
  // throughout (pause lives in dedicated columns, see booking.entity.ts);
  // pausedMinutes accumulates so billing can subtract idle time.

  private async loadActiveBooking(bookingId: string): Promise<Booking> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.status !== BookingStatus.ACTIVE) {
      throw new BadRequestException('Pause is only available during active work');
    }
    return booking;
  }

  /** Broadcast pause state to the pollers via the Redis status cache. */
  private async cachePauseState(booking: Booking): Promise<void> {
    await this.redisService.cacheBookingStatus(booking.id, {
      status: booking.status,
      operatorName: booking.operator?.name,
      arrivalOtp: null,
      pauseRequested: !!booking.pauseRequestedAt,
      paused: !!booking.pausedAt,
      pausedMinutes: booking.pausedMinutes ?? 0,
    });
  }

  async requestPause(bookingId: string, operatorUserId: string) {
    const booking = await this.loadActiveBooking(bookingId);
    if (booking.operator?.id !== operatorUserId) {
      throw new BadRequestException('Only the assigned worker can request a pause');
    }
    if (booking.pausedAt) throw new BadRequestException('Job is already paused');
    booking.pauseRequestedAt = new Date();
    await this.bookingsRepository.save(booking);
    await this.cachePauseState(booking);
    if (booking.customer?.id) {
      await this.notificationsService
        .sendToUser(booking.customer.id, {
          title: 'Pause requested',
          body: 'Your worker asked to pause the job timer. Approve or decline in the app.',
          data: { type: 'pause_requested', bookingId: booking.id },
        })
        .catch((err) => console.error('[RequestPause] notification failed:', err));
    }
    return { message: 'Pause request sent to customer', pauseRequested: true };
  }

  async respondPause(bookingId: string, customerUserId: string, approve: boolean) {
    const booking = await this.loadActiveBooking(bookingId);
    if (booking.customer?.id !== customerUserId) {
      throw new BadRequestException('Only the customer can respond to a pause request');
    }
    if (!booking.pauseRequestedAt) {
      throw new BadRequestException('No pending pause request');
    }
    booking.pauseRequestedAt = null as any;
    if (approve) booking.pausedAt = new Date();
    await this.bookingsRepository.save(booking);
    await this.cachePauseState(booking);
    if (booking.operator?.id) {
      await this.notificationsService
        .sendToUser(booking.operator.id, {
          title: approve ? 'Pause approved' : 'Pause declined',
          body: approve
            ? 'Timer stopped. Tap Resume when work continues.'
            : 'The customer declined the pause — keep working.',
          data: { type: approve ? 'pause_approved' : 'pause_declined', bookingId: booking.id },
        })
        .catch((err) => console.error('[RespondPause] notification failed:', err));
    }
    return { message: approve ? 'Pause approved' : 'Pause declined', paused: approve };
  }

  async resumeWork(bookingId: string, operatorUserId: string) {
    const booking = await this.loadActiveBooking(bookingId);
    if (booking.operator?.id !== operatorUserId) {
      throw new BadRequestException('Only the assigned worker can resume the job');
    }
    if (!booking.pausedAt) throw new BadRequestException('Job is not paused');
    const pausedMs = Date.now() - new Date(booking.pausedAt).getTime();
    booking.pausedMinutes = (booking.pausedMinutes ?? 0) + Math.max(0, Math.round(pausedMs / 60000));
    booking.pausedAt = null as any;
    await this.bookingsRepository.save(booking);
    await this.cachePauseState(booking);
    if (booking.customer?.id) {
      await this.notificationsService
        .sendToUser(booking.customer.id, {
          title: 'Work resumed',
          body: 'The job timer is running again.',
          data: { type: 'work_resumed', bookingId: booking.id },
        })
        .catch((err) => console.error('[ResumeWork] notification failed:', err));
    }
    return { message: 'Work resumed', pausedMinutes: booking.pausedMinutes };
  }

  // ── Dispute / report — persisted (was a log-only stub). Either party can
  // file; stored on the booking so admin review and support can act on it.
  async reportDispute(bookingId: string, userId: string, reason: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    const isCustomer = booking.customer?.id === userId;
    const isOperator = booking.operator?.id === userId;
    if (!isCustomer && !isOperator) {
      throw new BadRequestException('Only participants of this booking can report it');
    }
    booking.disputeReason = reason;
    booking.disputeReporterRole = isCustomer ? 'CUSTOMER' : 'WORKER';
    booking.disputedAt = new Date();
    await this.bookingsRepository.save(booking);
    return { success: true, message: 'Report submitted — our team will review it.' };
  }

  // ── Admin: disputes + bookings monitor (portal only) ──────────────────────

  /// Disputed bookings for the portal. open=true → unresolved only.
  async getDisputes(
    openOnly = false,
    page = 1,
    limit = 50,
  ): Promise<Booking[]> {
    const qb = this.bookingsRepository
      .createQueryBuilder('booking')
      .leftJoinAndSelect('booking.customer', 'customer')
      .leftJoinAndSelect('booking.operator', 'operator')
      .where('booking.disputedAt IS NOT NULL')
      .orderBy('booking.disputedAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit);
    if (openOnly) qb.andWhere('booking.disputeResolvedAt IS NULL');
    return qb.getMany();
  }

  async resolveDispute(bookingId: string, resolution: string): Promise<Booking> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (!booking.disputedAt) {
      throw new BadRequestException('This booking has no dispute to resolve');
    }
    booking.disputeResolution = resolution;
    booking.disputeResolvedAt = new Date();
    await this.bookingsRepository.save(booking);
    // Tell both parties the outcome (multicast — same payload).
    const partyIds = [booking.customer?.id, booking.operator?.id].filter(
      (id): id is string => !!id,
    );
    if (partyIds.length > 0) {
      await this.notificationsService
        .sendToUsers(partyIds, {
          title: 'Report resolved',
          body: 'The Gixbee team reviewed the report on your booking.',
          data: { type: 'dispute_resolved', bookingId },
        })
        .catch(() => {});
    }
    return booking;
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

  async getBookingById(id: string): Promise<Booking | null> {
    return this.bookingsRepository
      .createQueryBuilder('booking')
      .leftJoinAndSelect('booking.customer', 'customer')
      .leftJoinAndSelect('booking.operator', 'operator')
      .where('booking.id = :id', { id })
      .getOne();
  }

  /// SECURITY FIX: shared guard for the booking mutation endpoints that used
  /// to trust the URL id. Throws unless the caller is this booking's customer
  /// or operator.
  async assertParticipant(bookingId: string, userId: string): Promise<Booking> {
    const booking = await this.getBookingById(bookingId);
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.customer?.id !== userId && booking.operator?.id !== userId) {
      throw new BadRequestException('You are not a participant of this booking');
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
      order: { scheduledAt: 'DESC' },
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
      .orderBy('booking.scheduledAt', 'DESC')
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

  async addGpsStrike(bookingId: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) return;
    if (booking.status !== BookingStatus.ACCEPTED) return;

    booking.gpsStrikes += 1;
    await this.bookingsRepository.save(booking);

    if (booking.gpsStrikes >= 3) {
      booking.status = BookingStatus.CANCELLED;
      await this.bookingsRepository.save(booking);

      await this.redisService.cacheBookingStatus(bookingId, {
        status: 'CANCELLED',
        operatorName: booking.operator?.name,
      });

      if (booking.customer?.id) {
        await this.notificationsService.notifyBookingCancelled(
          booking.customer.id,
        );
      }
      if (booking.operator?.id) {
        await this.notificationsService.sendToUser(booking.operator.id, {
          title: 'Booking Forfeited',
          body: 'You received 3 GPS strikes. The job has been forfeited.',
          data: { type: 'booking_forfeited', bookingId },
        });
        await this.workersService.setWorkerStatus(booking.operator.id, 'available');
      }

      return { cancelled: true, strikes: 3 };
    }

    await this.notificationsService.notifyGpsStrike(
      booking.operator.id,
      booking.gpsStrikes,
    );

    return { cancelled: false, strikes: booking.gpsStrikes };
  }

  /**
   * Helper to calculate distance between two coordinates in km using Haversine formula
   */
  public calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371; // Radius of the earth in km
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c; // Distance in km
  }
}
