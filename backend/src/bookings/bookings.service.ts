import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, In } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { Booking, BookingStatus } from './booking.entity';
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

        const booking = await manager
          .createQueryBuilder(Booking, 'booking')
          .setLock('pessimistic_write')
          .leftJoinAndSelect('booking.customer', 'customer')
          .leftJoinAndSelect('booking.operator', 'operator')
          .where('booking.id = :bookingId', { bookingId })
          .getOne();

        if (!booking) throw new NotFoundException('Booking not found');
        console.log(`[AcceptBooking] Booking found — status=${booking.status}, operator=${booking.operator?.id}`);

        if (booking.status !== BookingStatus.REQUESTED) {
          throw new BadRequestException(
            'This booking is no longer available — it may have been accepted or cancelled.',
          );
        }

        if (booking.operator?.id !== workerId) {
          throw new BadRequestException('You are not assigned to this booking.');
        }

        // Transition this booking → ACCEPTED
        booking.status = BookingStatus.ACCEPTED;
        const saved = await manager.save(booking);
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
          opName: booking.operator?.name ?? null,
          customerId: booking.customer?.id ?? null,
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

    // Cache ACCEPTED status for poll endpoint
    try {
      await this.redisService.cacheBookingStatus(bookingId, {
        status: 'ACCEPTED',
        operatorName: operatorName,
        arrivalOtp: savedBooking.arrivalOtp,
      });
    } catch (e) {
      console.error('[AcceptBooking] cacheBookingStatus failed:', e);
    }

    // Notify cancelled customers
    for (const cancelled of otherPendingFiltered) {
      try {
        if (cancelled.customer?.id) {
          await this.notificationsService.notifyBookingCancelled(
            cancelled.customer.id,
            'The worker accepted another job. Please try booking again.',
          );
        }
        await this.redisService.removePendingBooking(workerId, cancelled.id).catch(() => {});
        await this.redisService.cacheBookingStatus(cancelled.id, {
          status: 'CANCELLED',
          operatorName: null,
        });
      } catch (e) {
        console.error(`[AcceptBooking] Cancelled-notification failed for ${cancelled.id}:`, e);
      }
    }

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
      return bookings.sort((a, b) => ids.indexOf(a.id) - ids.indexOf(b.id));
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
  ): Promise<{ message: string; status: string; billingHours: number }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.completionOtp || booking.completionOtp !== otp) {
      throw new BadRequestException('Invalid completion OTP');
    }

    this.redisService.deleteOtp(`otp:booking:${bookingId}:completion`).catch(() => {});

    if (booking.status !== BookingStatus.ACTIVE) {
      throw new BadRequestException('Job must be active to complete');
    }

    const startTime = booking.startedAt
      ? new Date(booking.startedAt).getTime()
      : Date.now();
    const hoursWorked = Math.max(
      1,
      Math.ceil((Date.now() - startTime) / (1000 * 60 * 60)),
    );

    booking.status = BookingStatus.COMPLETED;
    booking.completedAt = new Date();
    booking.billingHours = hoursWorked;
    await this.bookingsRepository.save(booking);

    await this.redisService.cacheBookingStatus(bookingId, {
      status: 'COMPLETED',
      operatorName: booking.operator?.name,
    });

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
    };
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

  async submitRating(
    bookingId: string,
    rating: number,
  ): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestException('Can only rate completed jobs');
    }

    booking.rating = rating;
    await this.bookingsRepository.save(booking);

    if (booking.operator?.id) {
      const workerProfile = await this.workerProfileRepo.findOne({
        where: { user: { id: booking.operator.id } },
      });
      if (workerProfile) {
        const currentTotal = workerProfile.rating * workerProfile.reviewCount;
        workerProfile.reviewCount += 1;
        workerProfile.rating =
          (currentTotal + rating) / workerProfile.reviewCount;
        await this.workerProfileRepo.save(workerProfile);
      }
    }

    return { message: 'Rating submitted successfully' };
  }

  async getBookingById(id: string): Promise<Booking | null> {
    return this.bookingsRepository
      .createQueryBuilder('booking')
      .leftJoinAndSelect('booking.customer', 'customer')
      .leftJoinAndSelect('booking.operator', 'operator')
      .where('booking.id = :id', { id })
      .getOne();
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
