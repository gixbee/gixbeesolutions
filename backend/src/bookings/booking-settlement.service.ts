import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { Booking, BookingStatus, BookingType } from './booking.entity';
import { WalletsService } from '../wallets/wallets.service';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { WorkersService } from '../workers/workers.service';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { WALLET_PAYMENTS_ENABLED } from '../common/money-model';
import { BookingStatusService } from './booking-status.service';

@Injectable()
export class BookingSettlementService {
  private readonly logger = new Logger(BookingSettlementService.name);

  private static readonly INSTANT_PETROL_PER_KM_DEFAULT = 10;

  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    @InjectRepository(WorkerProfile)
    private workerProfileRepo: Repository<WorkerProfile>,
    private walletsService: WalletsService,
    private notificationsService: NotificationsService,
    private redisService: RedisService,
    private workersService: WorkersService,
    private dataSource: DataSource,
    private outboxService: OutboxService,
    private masterEntriesService: MasterEntriesService,
    private bookingStatusService: BookingStatusService,
  ) {}

  private generateOtp(): string {
    return Math.floor(1000 + Math.random() * 9000).toString();
  }

  async verifyArrivalOtp(
    bookingId: string,
    otp: string,
  ): Promise<{ message: string; status: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.arrivalOtp || booking.arrivalOtp !== otp) {
      throw new BadRequestException('Invalid arrival OTP');
    }
    if (
      booking.status !== BookingStatus.ACCEPTED &&
      booking.status !== BookingStatus.ARRIVED
    ) {
      throw new BadRequestException(
        'Arrival OTP can only be verified after the pro has accepted / arrived.',
      );
    }

    this.redisService
      .deleteOtp(`otp:booking:${bookingId}:arrival`)
      .catch(() => {});

    booking.status = BookingStatus.ACTIVE;
    booking.startedAt = new Date();
    await this.bookingsRepository.save(booking);

    await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
      status: 'ACTIVE',
      operatorName: booking.operator?.name ?? null,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
    });

    return {
      message: 'Arrival confirmed. Job is now active.',
      status: 'ACTIVE',
    };
  }

  async verifyCompletionOtp(
    bookingId: string,
    otp: string,
  ): Promise<{
    message: string;
    status: string;
    billingHours: number;
    workedMinutes: number;
    hourlyRate: number;
    serviceAmount: number;
    petrolDistanceKm: number;
    petrolRatePerKm: number;
    petrolAmount: number;
    platformFee: number;
    paymentMethod: string;
    totalAmount: number;
    isPaid: boolean;
    needsManualPayment: boolean;
    customerName: string | null;
    workerName: string | null;
  }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.completionOtp || booking.completionOtp !== otp) {
      throw new BadRequestException('Invalid completion OTP');
    }

    this.redisService
      .deleteOtp(`otp:booking:${bookingId}:completion`)
      .catch(() => {});

    if (booking.status !== BookingStatus.ACTIVE) {
      throw new BadRequestException('Job must be active to complete');
    }

    const configuredPetrolRate =
      booking.type === BookingType.INSTANT
        ? Math.max(
            0,
            await this.masterEntriesService.getConfigNumber(
              'instant_petrol_per_km',
              BookingSettlementService.INSTANT_PETROL_PER_KM_DEFAULT,
            ),
          )
        : 0;

    // Claim + billing save + outbox in one TX so Redis/socket/worker-release
    // side effects survive a crash after commit (BOOKING_COMPLETED listener).
    const txResult = await this.dataSource.transaction(async (manager) => {
      // AUDIT FIX (double-settlement race): atomically claim the completion.
      const claim = await manager.update(
        Booking,
        { id: bookingId, status: BookingStatus.ACTIVE },
        { status: BookingStatus.COMPLETED, completedAt: new Date() },
      );
      if (!claim.affected) {
        throw new BadRequestException('Job must be active to complete');
      }

      const locked =
        (await manager.findOne(Booking, {
          where: { id: bookingId },
          relations: ['customer', 'operator'],
        })) ?? booking;

      const startTime = locked.startedAt
        ? new Date(locked.startedAt).getTime()
        : Date.now();
      // Bill full wall-clock time from start → complete (no pause deduction).
      const elapsedMs = Math.max(0, Date.now() - startTime);
      const workedMs = elapsedMs;
      // Floor at 1 minute so a near-instant completion still has a charge base.
      const workedMinutes = Math.max(1, Math.round(workedMs / 60000));
      const billingHours = Math.max(1, Math.ceil(workedMinutes / 60));

      locked.status = BookingStatus.COMPLETED;
      locked.completedAt = locked.completedAt ?? new Date();
      locked.billingHours = billingHours;
      locked.workedMinutes = workedMinutes;
      // INSTANT: amount is ₹/hr — min 1 hour then proportional. Others: flat.
      const hourlyRate = Number(locked.amount) || 0;
      const billableMinutes = Math.max(60, workedMinutes);
      const serviceAmount =
        locked.type === BookingType.INSTANT
          ? Math.round(hourlyRate * (billableMinutes / 60))
          : hourlyRate;
      const rawPetrolDistance = Number(locked.acceptDistanceKm);
      const petrolDistanceKm =
        locked.type === BookingType.INSTANT &&
        Number.isFinite(rawPetrolDistance) &&
        rawPetrolDistance > 0
          ? rawPetrolDistance
          : 0;
      const petrolRatePerKm =
        locked.type === BookingType.INSTANT
          ? Number(locked.petrolRatePerKm ?? configuredPetrolRate)
          : 0;
      const petrolAmount =
        locked.type === BookingType.INSTANT
          ? Math.round(petrolDistanceKm * petrolRatePerKm)
          : 0;
      const totalAmount = serviceAmount + petrolAmount;

      locked.petrolDistanceKm =
        locked.type === BookingType.INSTANT ? petrolDistanceKm : null;
      locked.petrolRatePerKm =
        locked.type === BookingType.INSTANT ? petrolRatePerKm : null;
      locked.petrolAmount =
        locked.type === BookingType.INSTANT ? petrolAmount : null;
      locked.totalAmount = totalAmount;

      // Instant Help settles offline. Non-instant WALLET path kept behind flag.
      if (
        WALLET_PAYMENTS_ENABLED &&
        locked.type !== BookingType.INSTANT &&
        locked.paymentMethod === 'WALLET'
      ) {
        if (totalAmount <= 0) {
          locked.isPaid = true;
        } else if (locked.customer?.id && locked.operator?.id) {
          try {
            await this.walletsService.transferForBooking(
              locked.customer.id,
              locked.operator.id,
              totalAmount,
              bookingId,
            );
            locked.isPaid = true;
            console.log(
              `[CompleteBooking] Wallet settled: ₹${totalAmount} customer→worker for ${bookingId}`,
            );
          } catch (error) {
            locked.isPaid = false;
            console.error(
              '[CompleteBooking] Wallet settlement failed — falling back to direct collection:',
              error?.message ?? error,
            );
          }
        }
      } else if (locked.type === BookingType.INSTANT) {
        locked.isPaid = false;
      }

      await manager.save(locked);

      const outbox = await this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_COMPLETED,
        bookingId,
        {
          bookingId,
          customerId: locked.customer?.id ?? null,
          operatorId: locked.operator?.id ?? null,
          operatorName: locked.operator?.name ?? null,
          isPaid: !!locked.isPaid,
          workerPaidConfirmed: !!locked.workerPaidConfirmed,
          customerPaidConfirmed: !!locked.customerPaidConfirmed,
        },
      );

      return {
        locked,
        outboxId: outbox.id,
        billingHours,
        workedMinutes,
        hourlyRate,
        serviceAmount,
        petrolDistanceKm,
        petrolRatePerKm,
        petrolAmount,
        totalAmount,
      };
    });

    await this.outboxService.enqueueDispatch(txResult.outboxId);

    await this.bookingStatusService
      .cacheAndEmitBookingStatus(bookingId, {
        status: 'COMPLETED',
        operatorName: txResult.locked.operator?.name ?? null,
        operatorId: txResult.locked.operator?.id ?? null,
        customerId: txResult.locked.customer?.id ?? null,
        isPaid: !!txResult.locked.isPaid,
        workerPaidConfirmed: !!txResult.locked.workerPaidConfirmed,
        customerPaidConfirmed: !!txResult.locked.customerPaidConfirmed,
      })
      .catch(() => undefined);

    // First-job bonus stays in-service (wallet product side-effect).
    const completed = txResult.locked;
    if (completed.operator?.id) {
      const workerProfile = await this.workerProfileRepo.findOne({
        where: { user: { id: completed.operator.id } },
      });
      if (workerProfile && !workerProfile.isFirstJobDone) {
        const periodicJobs = await this.workersService
          .periodicJobsPerPayment()
          .catch(() => 0);
        if (WALLET_PAYMENTS_ENABLED && periodicJobs <= 0) {
          await this.walletsService.addFunds(completed.operator.id, 12);
        }
        workerProfile.isFirstJobDone = true;
        await this.workerProfileRepo.save(workerProfile);
      }
    }

    const platformFee = 12;
    return {
      message: 'Job completed successfully.',
      status: 'COMPLETED',
      billingHours: txResult.billingHours,
      workedMinutes: txResult.workedMinutes,
      hourlyRate: txResult.hourlyRate,
      serviceAmount: txResult.serviceAmount,
      petrolDistanceKm: txResult.petrolDistanceKm,
      petrolRatePerKm: txResult.petrolRatePerKm,
      petrolAmount: txResult.petrolAmount,
      platformFee,
      paymentMethod: completed.paymentMethod,
      totalAmount: txResult.totalAmount,
      isPaid: completed.isPaid,
      needsManualPayment: !completed.isPaid,
      customerName: completed.customer?.name ?? null,
      workerName: completed.operator?.name ?? null,
    };
  }

  // AUDIT FIX: was callable by ANY authenticated user on ANY booking. Only
  // the booking's participants may mark it paid, and only after completion.
  // Dual confirm: worker + customer each confirm offline collection; `isPaid`
  // flips only when both sides have confirmed (or when a role re-confirms
  // after the other already has).
  async markPaid(
    bookingId: string,
    userId: string,
    body: {
      collectionMethod?: string;
      honestyCheck?: string;
      safetyCheck?: string;
    } = {},
  ): Promise<{
    message: string;
    isPaid: boolean;
    workerPaidConfirmed: boolean;
    customerPaidConfirmed: boolean;
  }> {
    const txResult = await this.dataSource.transaction(async (manager) => {
      const bookings = manager.getRepository(Booking);
      const booking = await bookings
        .createQueryBuilder('booking')
        .innerJoinAndSelect('booking.customer', 'customer')
        .leftJoinAndSelect('booking.operator', 'operator')
        .setLock('pessimistic_write', undefined, ['booking'])
        .where('booking.id = :bookingId', { bookingId })
        .getOne();
      if (!booking) throw new NotFoundException('Booking not found');
      const isWorker = booking.operator?.id === userId;
      const isCustomer = booking.customer?.id === userId;
      if (!isWorker && !isCustomer) {
        throw new BadRequestException(
          'Only participants of this booking can mark it paid',
        );
      }
      if (booking.status !== BookingStatus.COMPLETED) {
        throw new BadRequestException(
          'Only completed bookings can be marked paid',
        );
      }

      if (isWorker) {
        booking.workerPaidConfirmed = true;
        if (body.honestyCheck) {
          booking.workerHonestyCheck = body.honestyCheck;
        }
      }
      if (isCustomer) {
        booking.customerPaidConfirmed = true;
        if (body.collectionMethod) {
          booking.paymentCollectionMethod = body.collectionMethod;
        }
        if (body.safetyCheck) {
          booking.customerSafetyCheck = body.safetyCheck;
        }
      }

      // Fully paid once both sides confirm. A single-sided confirm (e.g. older
      // client that only had the worker button) still marks paid if the other
      // side already confirmed, or if this is the first confirm and the other
      // role is missing from the booking.
      const bothConfirmed =
        !!booking.workerPaidConfirmed && !!booking.customerPaidConfirmed;
      const otherMissing =
        (isWorker && !booking.customer?.id) ||
        (isCustomer && !booking.operator?.id);
      if (bothConfirmed || otherMissing || booking.isPaid) {
        booking.isPaid = true;
      }

      await manager.save(booking);
      const outbox = await this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_PAYMENT_CONFIRMED,
        bookingId,
        {
          bookingId,
          customerId: booking.customer?.id ?? null,
          operatorId: booking.operator?.id ?? null,
          operatorName: booking.operator?.name ?? null,
          status: booking.status,
          isPaid: !!booking.isPaid,
          workerPaidConfirmed: !!booking.workerPaidConfirmed,
          customerPaidConfirmed: !!booking.customerPaidConfirmed,
        },
      );
      return { outboxId: outbox.id, booking };
    });

    const { booking } = txResult;
    await this.outboxService.enqueueDispatch(txResult.outboxId);

    await this.bookingStatusService
      .cacheAndEmitBookingStatus(bookingId, {
        status: booking.status,
        operatorName: booking.operator?.name ?? null,
        operatorId: booking.operator?.id ?? null,
        customerId: booking.customer?.id ?? null,
        isPaid: !!booking.isPaid,
        workerPaidConfirmed: !!booking.workerPaidConfirmed,
        customerPaidConfirmed: !!booking.customerPaidConfirmed,
      })
      .catch(() => undefined);

    return {
      message: booking.isPaid
        ? 'Booking marked as paid.'
        : 'Payment confirmation recorded. Waiting for the other party.',
      isPaid: !!booking.isPaid,
      workerPaidConfirmed: !!booking.workerPaidConfirmed,
      customerPaidConfirmed: !!booking.customerPaidConfirmed,
    };
  }

  async refreshCompletionOtp(bookingId: string): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    const newOtp = this.generateOtp();
    booking.completionOtp = newOtp;
    await this.bookingsRepository.save(booking);
    await this.redisService.saveOtp(
      `otp:booking:${bookingId}:completion`,
      newOtp,
    );

    if (booking.customer?.id) {
      await this.notificationsService.notifyCustomerJobComplete(
        booking.customer.id,
        newOtp,
      );
    }

    return { message: 'Completion OTP refreshed' };
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
    let ratedOperatorId: string | null = null;
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
      ratedOperatorId = booking.operator.id;
    });

    // Keep the dispatch snapshot's rating fresh — snapshots live 24h, and
    // broadcast targeting sorts on rating. Fire-and-forget: a failed refresh
    // just means the next cold miss rebuilds it.
    if (ratedOperatorId) {
      this.workersService
        .refreshWorkerSnapshot(ratedOperatorId)
        .catch((e) =>
          this.logger.error(
            `[SubmitRating] snapshot refresh failed: ${e?.message ?? e}`,
          ),
        );
    }

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
      throw new BadRequestException(
        'Only the assigned worker can rate this customer',
      );
    }
    if (booking.status !== BookingStatus.COMPLETED) {
      throw new BadRequestException('Can only rate completed jobs');
    }
    booking.customerRating = rating;
    await this.bookingsRepository.save(booking);
    return { message: 'Customer rating submitted' };
  }

  async reportDispute(bookingId: string, userId: string, reason: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    const isCustomer = booking.customer?.id === userId;
    const isOperator = booking.operator?.id === userId;
    if (!isCustomer && !isOperator) {
      throw new BadRequestException(
        'Only participants of this booking can report it',
      );
    }
    booking.disputeReason = reason;
    booking.disputeReporterRole = isCustomer ? 'CUSTOMER' : 'WORKER';
    booking.disputedAt = new Date();
    await this.bookingsRepository.save(booking);
    return {
      success: true,
      message: 'Report submitted — our team will review it.',
    };
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

  async resolveDispute(
    bookingId: string,
    resolution: string,
  ): Promise<Booking> {
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

  /**
   * Worker announces arrival — transition ACCEPTED → ARRIVED, then FCM the
   * arrival OTP to the customer. Only the assigned operator may call this.
   */
  async notifyArrival(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string; status: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== workerId) {
      throw new NotFoundException('Booking not found');
    }
    if (
      booking.status !== BookingStatus.ACCEPTED &&
      booking.status !== BookingStatus.ARRIVED
    ) {
      throw new BadRequestException(
        'Arrival can only be marked while the job is accepted.',
      );
    }

    if (booking.status === BookingStatus.ACCEPTED) {
      booking.status = BookingStatus.ARRIVED;
      await this.bookingsRepository.save(booking);
      await this.bookingStatusService
        .cacheAndEmitBookingStatus(bookingId, {
          status: 'ARRIVED',
          operatorName: booking.operator?.name ?? null,
          operatorId: workerId,
          customerId: booking.customer?.id ?? null,
          arrivalOtp: booking.arrivalOtp,
        })
        .catch(() => undefined);
    }

    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Worker has arrived',
        body: `Arrival OTP: ${booking.arrivalOtp}. Share this with the worker to begin.`,
        data: {
          type: 'booking_status_update',
          bookingId,
          status: 'ARRIVED',
        },
      });
    }
    return { message: 'Arrival OTP sent to customer.', status: 'ARRIVED' };
  }

  /**
   * Worker marks job complete — FCM the completion OTP to the customer.
   * Only the assigned operator may call this.
   */
  async notifyCompletion(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== workerId) {
      throw new NotFoundException('Booking not found');
    }
    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'Job marked as complete',
        body: `Completion OTP: ${booking.completionOtp}. Enter this to confirm and close the job.`,
      });
    }
    return { message: 'Completion OTP sent to customer.' };
  }
}
