import {
  Injectable,
  BadRequestException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, In } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { Booking, BookingStatus, BookingType } from './booking.entity';
import { User } from '../users/user.entity';
import { WalletsService } from '../wallets/wallets.service';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import {
  MAX_BROADCAST_FANOUT,
  REBROADCAST_RADIUS_STRETCH,
  WorkersService,
} from '../workers/workers.service';
import { WorkerStrikeType } from '../workers/worker-strike.entity';
import type { WorkerDto } from '../workers/workers.service';
import { MessagesGateway } from '../messages/messages.gateway';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { JobCreditsService } from '../billing/job-credits.service';
import { CreditTransactionReason } from '../billing/credit-transaction.entity';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import {
  DEFAULT_BOOKING_PAYMENT_METHOD,
  WALLET_PAYMENTS_ENABLED,
} from '../common/money-model';

@Injectable()
export class BookingsService {
  private readonly logger = new Logger(BookingsService.name);

  /** Free unilateral cancel for this many minutes after ACCEPTED. */
  private static readonly CANCEL_GRACE_MINUTES = 3;
  private static readonly LATE_CANCEL_STRIKE_THRESHOLD = 3;
  private static readonly COMP_PER_KM_DEFAULT = 10;
  private static readonly COMP_MIN_INR_DEFAULT = 49;
  private static readonly COMP_MAX_INR_DEFAULT = 299;
  private static readonly INSTANT_PETROL_PER_KM_DEFAULT = 10;

  /** Worker GPS must be this fresh for a progress check to pass. */
  private static readonly GPS_LOCATION_MAX_AGE_MS = 90_000;
  /** Within this distance of the job counts as progressed. */
  private static readonly PROGRESS_NEAR_JOB_KM = 0.5;
  /** Must close at least this much distance vs accept snapshot. */
  private static readonly PROGRESS_MIN_CLOSER_KM = 0.3;
  /** Progress violations before customer gets free cancel. */
  private static readonly PROGRESS_STRIKE_THRESHOLD = 2;


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
    private messagesGateway: MessagesGateway,
    private outboxService: OutboxService,
    private jobCreditsService: JobCreditsService,
    private masterEntriesService: MasterEntriesService,
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
    const customerId =
      (bookingData.customer as any)?.id ?? bookingData.customer;
    const operatorId =
      (bookingData.operator as any)?.id ?? bookingData.operator;

    if (customerId) {
      await this.assertInstantHelpAllowed(String(customerId));
    }

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
      paymentMethod:
        bookingData.paymentMethod || DEFAULT_BOOKING_PAYMENT_METHOD,
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

    // Schedule 90-second request timeout. Stable jobId so retries / double
    // submits collapse onto one delayed job (matches broadcast outbox path).
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: savedBooking.id, attempt: 1 },
      {
        jobId: `requestTimeout:${savedBooking.id}`,
        delay: 90 * 1000,
        removeOnComplete: true,
      },
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
      // Realtime companion to FCM — clients treat this as primary, poll as fallback.
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
      } catch (e) {
        console.error('[CreateBooking] socket emit failed:', e);
      }
    }

    // Cache initial status and emit over socket
    await this.cacheAndEmitBookingStatus(savedBooking.id, {
      status: 'REQUESTED',
      operatorName: null,
      operatorId: operatorId ?? null,
      customerId: customerId ?? null,
      arrivalOtp: savedBooking.arrivalOtp,
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
    await this.assertInstantHelpAllowed(customerId);

    // Find eligible pros FIRST — no point persisting a request nobody can see.
    const nearby = await this.workersService.getNearby(
      customerId,
      data.skill,
      data.serviceLat,
      data.serviceLng,
    );

    const targets = this.selectBroadcastTargets(
      nearby,
      data.preferredLanguages,
    );

    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();

    // First name only for the pre-accept card (privacy: full name after accept).
    const customer = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: customerId }, select: ['id', 'name'] })
      .catch(() => null);
    const customerFirstName =
      customer?.name?.trim().split(/\s+/)[0] || undefined;

    // Eligible worker ids known before persist — carried in outbox payload so
    // FCM / socket / Redis pending can run after commit (retryable).
    const notifiedWorkerIds = targets.map((w) => w.id);

    const { savedBooking, outboxId } = await this.dataSource.transaction(
      async (manager) => {
        const booking = manager.create(Booking, {
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
          paymentMethod: data.paymentMethod || DEFAULT_BOOKING_PAYMENT_METHOD,
          status: BookingStatus.REQUESTED,
          arrivalOtp,
          completionOtp,
        });
        const saved = await manager.save(booking);

        const outbox = await this.outboxService.append(
          manager,
          OutboxEventType.BOOKING_BROADCAST_CREATED,
          saved.id,
          {
            bookingId: saved.id,
            customerId,
            customerName: customerFirstName,
            skill: data.skill,
            serviceLocation: data.serviceLocation,
            serviceLat: data.serviceLat,
            serviceLng: data.serviceLng,
            amount: data.amount,
            description: data.description,
            preferredLanguages: data.preferredLanguages,
            createdAt: (saved.createdAt ?? new Date()).toISOString(),
            arrivalOtp,
            completionOtp,
            notifiedWorkerIds,
            attempt: 1,
          },
        );
        return { savedBooking: saved, outboxId: outbox.id };
      },
    );

    await this.outboxService.enqueueDispatch(outboxId);

    console.log(
      `[BroadcastBooking] ${savedBooking.id} queued fan-out to ${notifiedWorkerIds.length} pros for ${data.skill}`,
    );
    return { booking: savedBooking, notified: notifiedWorkerIds.length };
  }

  /**
   * v126 language matching + fan-out shaping shared by the initial broadcast
   * AND the timeout rebroadcast. When the customer requires languages, notify
   * only pros with an overlap; pros with no languages set (null/empty) are
   * INCLUDED — lenient by design so legacy profiles keep receiving jobs.
   * Then nearest-first, rating tie-break, capped at MAX_BROADCAST_FANOUT.
   */
  private selectBroadcastTargets(
    nearby: WorkerDto[],
    preferredLanguages?: string[],
  ): WorkerDto[] {
    const wanted = (preferredLanguages ?? []).map((l) => l.toLowerCase());
    const languageEligible =
      wanted.length === 0
        ? nearby
        : nearby.filter((w) => {
            const spoken = (w.languages ?? []).map((l) => l.toLowerCase());
            return (
              spoken.length === 0 || spoken.some((l) => wanted.includes(l))
            );
          });

    return [...languageEligible]
      .sort((a, b) => {
        const d = (a.distance_km ?? Infinity) - (b.distance_km ?? Infinity);
        if (d !== 0) return d;
        return (b.rating || 0) - (a.rating || 0);
      })
      .slice(0, MAX_BROADCAST_FANOUT);
  }

  /**
   * Attempt-2 fan-out when NOBODY accepted within the first 90s window
   * (called by the requestTimeout job — see BookingsProcessor).
   *
   * Widening strategy:
   *  - re-runs the geo search (pros who came online since attempt 1 appear)
   *  - stretches each pro's own travel radius by REBROADCAST_RADIUS_STRETCH
   *    ("slightly beyond your usual area" — the incoming card shows the real
   *    distance, so the pro still decides)
   *  - notifies ONLY pros not already pinged in attempt 1 (never re-ping)
   *  - tells the customer the search was expanded (socket + FCM)
   *
   * The FINAL 90s timeout is scheduled here unconditionally — even with zero
   * new pros, attempt-1 pros still hold the request and may yet accept.
   */
  async rebroadcastBooking(
    bookingId: string,
  ): Promise<{ stillOpen: boolean; notified: number }> {
    const booking = await this.getBookingById(bookingId);
    if (
      !booking ||
      booking.status !== BookingStatus.REQUESTED ||
      booking.operator ||
      booking.type !== BookingType.INSTANT
    ) {
      return { stillOpen: false, notified: 0 };
    }

    // Final window is scheduled FIRST so a crash mid-rebroadcast can never
    // leave the request open forever. jobId dedupes retries.
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId, attempt: 2 },
      {
        jobId: `requestTimeout:${bookingId}:final`,
        delay: 90 * 1000,
        removeOnComplete: true,
      },
    );

    const alreadyNotified = new Set(await this.getNotifiedWorkerIds(bookingId));

    const nearby = await this.workersService.getNearby(
      booking.customer?.id ?? '',
      booking.skill,
      Number(booking.serviceLat),
      Number(booking.serviceLng),
      REBROADCAST_RADIUS_STRETCH,
    );
    const fresh = this.selectBroadcastTargets(
      nearby.filter((w) => !alreadyNotified.has(w.id)),
      booking.preferredLanguages,
    );
    const freshIds = fresh.map((w) => w.id);

    // Tell the customer we widened the search (best-effort — poll cache
    // still shows REQUESTED, so nothing breaks if both channels miss).
    if (booking.customer?.id) {
      try {
        this.messagesGateway.emitUserEvent(
          booking.customer.id,
          'booking_search_expanded',
          {
            bookingId,
            id: bookingId,
            newWorkersNotified: freshIds.length,
          },
        );
      } catch {}
      await this.notificationsService
        .sendToUser(booking.customer.id, {
          title: 'Still searching…',
          body:
            freshIds.length > 0
              ? `We expanded the search area and notified ${freshIds.length} more ${booking.skill} pro${freshIds.length === 1 ? '' : 's'}.`
              : 'We expanded the search area — still looking for an available pro.',
          data: { type: 'booking_search_expanded', bookingId },
        })
        .catch(() => {});
    }

    if (freshIds.length === 0) {
      this.logger.log(
        `[Rebroadcast] ${bookingId}: no new pros in the widened area`,
      );
      return { stillOpen: true, notified: 0 };
    }

    // Same outbox event as attempt 1 — the listener handles attempt 2 by
    // MERGING the notified set and skipping the (already scheduled) timeout.
    const outbox = await this.dataSource.transaction(async (manager) =>
      this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_BROADCAST_CREATED,
        bookingId,
        {
          bookingId,
          customerId: booking.customer?.id ?? '',
          customerName:
            booking.customer?.name?.trim().split(/\s+/)[0] || undefined,
          skill: booking.skill,
          serviceLocation: booking.serviceLocation,
          serviceLat: Number(booking.serviceLat),
          serviceLng: Number(booking.serviceLng),
          amount: Number(booking.amount),
          description: booking.description,
          preferredLanguages: booking.preferredLanguages,
          createdAt: (booking.createdAt ?? new Date()).toISOString(),
          arrivalOtp: booking.arrivalOtp,
          completionOtp: booking.completionOtp,
          notifiedWorkerIds: freshIds,
          attempt: 2,
        },
      ),
    );
    await this.outboxService.enqueueDispatch(outbox.id);

    this.logger.log(
      `[Rebroadcast] ${bookingId}: widened wave queued to ${freshIds.length} new pros`,
    );
    return { stillOpen: true, notified: freshIds.length };
  }

  async acceptBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string; status: string; booking: any }> {
    console.log(
      `[AcceptBooking] START — bookingId=${bookingId}, workerId=${workerId}`,
    );

    // ── STEP 1: Database transaction (only DB writes that MUST be atomic) ──
    let savedBooking: Booking;
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
        console.log(
          `[AcceptBooking] Locked booking — status=${lockedBooking.status}`,
        );

        if (lockedBooking.status !== BookingStatus.REQUESTED) {
          if (lockedBooking.status === BookingStatus.ACCEPTED) {
            const booking = await manager.findOne(Booking, {
              where: { id: bookingId },
              relations: ['customer', 'operator'],
            });
            if (booking?.operator?.id === workerId) {
              console.log(
                `[AcceptBooking] Idempotent retry by worker ${workerId} on already ACCEPTED booking ${bookingId}`,
              );
              (booking as any)._idempotent = true;
              return {
                saved: booking,
                opName: booking.operator?.name ?? null,
                customerId: booking.customer?.id ?? null,
                outboxId: null,
              };
            }
          }
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
        console.log(
          `[AcceptBooking] Booking loaded — operator=${booking.operator?.id}`,
        );

        // Step 2.5: Consume 1 job credit (throws if balance < 1)
        console.log(`[AcceptBooking] Consuming credit for worker ${workerId}`);
        const remainingCredits = await this.jobCreditsService.consumeCredit(
          workerId,
          bookingId,
          manager,
        );

        if (remainingCredits === 0) {
          console.log(
            `[AcceptBooking] Worker ${workerId} is out of credits. Forcing offline.`,
          );
          await this.workersService.forceOffline(workerId);
          this.notificationsService.sendToUser(workerId, {
            title: 'Out of credits',
            body: 'You have been taken offline because you have no job credits left. Buy a pack to receive new jobs.',
            data: { type: 'out_of_credits' },
          });
        }

        if (!booking.operator) {
          // Broadcast request (v126 first-accept-wins): no worker was
          // pre-assigned. The pessimistic row lock above makes this claim
          // atomic — the first accepter flips REQUESTED→ACCEPTED and later
          // accepters fail the REQUESTED check with a clean 400.
          booking.operator = { id: workerId } as any;
          console.log(`[AcceptBooking] Broadcast claim by worker ${workerId}`);
        } else if (booking.operator.id !== workerId) {
          throw new BadRequestException(
            'You are not assigned to this booking.',
          );
        }

        // Transition this booking → ACCEPTED
        booking.status = BookingStatus.ACCEPTED;
        booking.acceptedAt = new Date();

        // Snapshot worker GPS at accept so later progress checks can tell
        // "still sitting" from "heading to the customer".
        const acceptLoc =
          await this.redisService.getWorkerLocation(workerId);
        if (
          acceptLoc &&
          Number.isFinite(acceptLoc.lat) &&
          Number.isFinite(acceptLoc.lng)
        ) {
          booking.acceptLat = Number(acceptLoc.lat);
          booking.acceptLng = Number(acceptLoc.lng);
          const jobLat = Number(booking.serviceLat);
          const jobLng = Number(booking.serviceLng);
          if (Number.isFinite(jobLat) && Number.isFinite(jobLng)) {
            booking.acceptDistanceKm =
              Math.round(
                this.calculateDistance(
                  booking.acceptLat,
                  booking.acceptLng,
                  jobLat,
                  jobLng,
                ) * 100,
              ) / 100;
          }
        }

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
          console.log(
            `[AcceptBooking] Cancelling ${filtered.length} other pending bookings`,
          );
          await manager.update(
            Booking,
            { id: In(filtered.map((b) => b.id)) },
            { status: BookingStatus.CANCELLED },
          );
        }

        const customerId = saved.customer?.id ?? null;
        const opName = saved.operator?.name ?? null;
        const outbox = await this.outboxService.append(
          manager,
          OutboxEventType.BOOKING_ACCEPTED,
          bookingId,
          {
            bookingId,
            workerId,
            customerId,
            operatorName: opName,
            arrivalOtp: saved.arrivalOtp ?? null,
            cancelledBookingIds: filtered.map((b) => b.id),
            cancelledCustomerIds: filtered
              .map((c) => c.customer?.id)
              .filter((id): id is string => !!id),
          },
        );

        return {
          saved,
          opName,
          customerId,
          outboxId: outbox.id,
        };
      });

      savedBooking = txResult.saved;
      operatorName = txResult.opName;
      console.log('[AcceptBooking] Transaction committed successfully');

      // Kick dispatcher after commit (poller is the crash-safety net).
      if (txResult.outboxId) {
        await this.outboxService.enqueueDispatch(txResult.outboxId);
      }
    } catch (error) {
      console.error(
        '[AcceptBooking] Transaction FAILED:',
        error?.message ?? error,
      );
      throw error;
    }

    // ── STEP 2: Money side effect (kept in service; non-fatal) ──────────────
    // FCM / socket / Redis / GPS jobs moved to outbox listener (BOOKING_ACCEPTED).

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
        serviceLat: savedBooking.serviceLat,
        serviceLng: savedBooking.serviceLng,
        arrivalOtp: savedBooking.arrivalOtp,
        completionOtp: savedBooking.completionOtp,
        createdAt: savedBooking.createdAt,
        customer: savedBooking.customer
          ? { id: savedBooking.customer.id }
          : null,
        operator: {
          id: workerId,
          name: operatorName,
        },
      },
    };
  }

  // ── Reject / Decline Booking ──────────────────────────────────────────────

  /**
   * Worker declines one booking from their own queue.
   *
   * Targeted (operator already assigned to this worker): mark REJECTED and
   * notify the customer.
   *
   * Broadcast Instant Help (operator null, fan-out to many pros): only remove
   * THIS worker from Redis pending + booking:notified. Booking stays REQUESTED
   * so other eligible workers can still accept. Never re-notify the decliner.
   */
  async rejectBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });

    if (!booking) throw new NotFoundException('Booking not found');

    if (booking.status !== BookingStatus.REQUESTED) {
      throw new BadRequestException('Only pending requests can be declined.');
    }

    const isAssignedOperator = booking.operator?.id === workerId;
    const pendingIds = await this.redisService.getPendingBookingIds(workerId);
    const inPending = pendingIds.includes(bookingId);
    const notified = await this.getNotifiedWorkerIds(bookingId);
    const inNotified = notified.includes(workerId);

    if (!isAssignedOperator && !inPending && !inNotified) {
      throw new NotFoundException('Booking not found');
    }

    // Permanent removal from this worker's queue — poll/socket/FCM must not
    // surface this booking to them again while it stays open for others.
    await this.redisService.removePendingBooking(workerId, bookingId);
    await this.dropWorkerFromNotified(bookingId, workerId, notified);

    if (booking.customer?.id && booking.skill) {
      // Avoid pinging them again if the customer immediately creates a new request
      await this.redisService.markWorkerRejectedJob(
        booking.customer.id,
        booking.skill,
        workerId,
      );
    }

    if (isAssignedOperator) {
      booking.status = BookingStatus.REJECTED;
      await this.bookingsRepository.save(booking);

      await this.cacheAndEmitBookingStatus(bookingId, {
        status: 'REJECTED',
        operatorName: null,
        operatorId: workerId,
        customerId: booking.customer?.id ?? null,
      });

      if (booking.customer?.id) {
        await this.notificationsService.notifyBookingCancelled(
          booking.customer.id,
          'The worker is unavailable for this request. Please try again.',
        );
      }
    }

    return { message: 'Booking declined.' };
  }

  /** Worker ids that received a broadcast Instant Help fan-out. */
  private async getNotifiedWorkerIds(bookingId: string): Promise<string[]> {
    try {
      const raw = await this.redisService.get(`booking:notified:${bookingId}`);
      if (!raw) return [];
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed)
        ? parsed.filter((id): id is string => typeof id === 'string')
        : [];
    } catch {
      return [];
    }
  }

  private async dropWorkerFromNotified(
    bookingId: string,
    workerId: string,
    notified?: string[],
  ): Promise<void> {
    const list = notified ?? (await this.getNotifiedWorkerIds(bookingId));
    if (list.length === 0) return;
    const remaining = list.filter((id) => id !== workerId);
    try {
      if (remaining.length === 0) {
        await this.redisService.del(`booking:notified:${bookingId}`);
      } else {
        await this.redisService.set(
          `booking:notified:${bookingId}`,
          JSON.stringify(remaining),
          60 * 60,
        );
      }
    } catch (e) {
      console.error(
        `[RejectBooking] notified update failed for ${bookingId}:`,
        e,
      );
    }
  }

  /**
   * Pull a booking out of every notified worker's pending queue (and drop the
   * notified set). Used when the request ends for everyone: accept (other
   * workers), customer cancel, timeout, or whole-booking reject.
   */
  private async clearAllNotifiedPending(bookingId: string): Promise<void> {
    const notified = await this.getNotifiedWorkerIds(bookingId);
    if (notified.length === 0) return;
    await Promise.all(
      notified.map((wid) =>
        this.redisService.removePendingBooking(wid, bookingId).catch(() => {}),
      ),
    );
    await this.redisService
      .del(`booking:notified:${bookingId}`)
      .catch(() => {});
  }

  // ── Update Status ─────────────────────────────────────────────────────────

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
      await this.cacheAndEmitBookingStatus(id, {
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
  async timeoutCancelBooking(
    bookingId: string,
  ): Promise<{ cancelled: boolean }> {
    let outboxId: string | null = null;
    const cancelled = await this.dataSource.transaction(async (manager) => {
      const claim = await manager.update(
        Booking,
        { id: bookingId, status: BookingStatus.REQUESTED },
        {
          status: BookingStatus.CANCELLED,
          cancellationReason: 'No worker accepted in time',
        },
      );
      if (!claim.affected) return false;

      const booking = await manager.findOne(Booking, {
        where: { id: bookingId },
        relations: ['customer', 'operator'],
      });
      const outbox = await this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_CANCELLED,
        bookingId,
        {
          bookingId,
          reason: 'No worker accepted in time',
          source: 'timeout',
          operatorId: booking?.operator?.id ?? null,
          operatorName: booking?.operator?.name ?? null,
          customerId: booking?.customer?.id ?? null,
        },
      );
      outboxId = outbox.id;
      return true;
    });
    if (outboxId) {
      await this.outboxService.enqueueDispatch(outboxId);
    }
    return { cancelled };
  }

  /**
   * Cancels a booking. Unilateral customer cancel is gated by stage:
   * - REQUESTED / ACCEPTED within grace → free
   * - ACCEPTED past grace → allowed with late-cancel strike
   * - ACCEPTED + workerNoProgressAt → free (no strike, no credit refund)
   * - ARRIVED / ACTIVE → blocked (use cancel-request)
   * Worker-approved cancels call this with applyLateCancelStrike=false.
   */
  async cancelBooking(
    id: string,
    reason: string,
    source: 'customer' | 'operator' = 'customer',
    opts?: {
      applyLateCancelStrike?: boolean;
      skipStageGate?: boolean;
      refundJobCredit?: boolean;
    },
  ): Promise<{
    status: string;
    refundAmount: number;
    refundMethod: string;
    message: string;
    lateCancelStrike?: boolean;
    strikeCount?: number;
    instantHelpBlocked?: boolean;
    compensationAmount?: number | null;
    compensationDistanceKm?: number | null;
    workerNoProgress?: boolean;
  }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.status === BookingStatus.COMPLETED) {
      throw new BadRequestException('Completed bookings cannot be cancelled.');
    }

    const freeDueToNoProgress =
      source === 'customer' &&
      !!booking.workerNoProgressAt &&
      booking.status === BookingStatus.ACCEPTED;

    const applyStrike =
      source === 'customer' &&
      opts?.applyLateCancelStrike !== false &&
      !freeDueToNoProgress;
    let lateCancelStrike = false;
    let strikeCount: number | undefined;
    let instantHelpBlocked = false;
    let compensationAmount: number | null = null;
    let compensationDistanceKm: number | null = null;

    if (source === 'customer' && !opts?.skipStageGate) {
      const st = booking.status;
      if (st === BookingStatus.ARRIVED || st === BookingStatus.ACTIVE) {
        throw new BadRequestException(
          'This job has already started or the pro has arrived. Ask your pro to approve a cancellation instead.',
        );
      }
      if (
        st === BookingStatus.ACCEPTED &&
        !freeDueToNoProgress &&
        !this.isWithinCancelGrace(booking)
      ) {
        // Allowed with strike — applied after successful cancel below.
        lateCancelStrike = applyStrike;
      }
    }

    const cancelReason = freeDueToNoProgress
      ? `${reason} [WORKER_NO_PROGRESS]`
      : reason;

    booking.status = BookingStatus.CANCELLED;
    booking.cancellationReason = cancelReason;
    booking.cancelRequestedAt = null as any;

    // Refund policy: refund only money Gixbee actually captured.
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

    const shouldRefundCredit =
      source === 'customer' &&
      !!booking.operator?.id &&
      opts?.refundJobCredit !== false &&
      !freeDueToNoProgress;

    const outbox = await this.dataSource.transaction(async (manager) => {
      await manager.save(booking);

      if (shouldRefundCredit && booking.operator?.id) {
        console.log(
          `[CancelBooking] Refunding 1 job credit to worker ${booking.operator.id} due to customer cancellation`,
        );
        await this.jobCreditsService.refundCredit(
          booking.operator.id,
          id,
          CreditTransactionReason.REFUND_CUSTOMER_CANCEL,
          manager,
        );
      }

      if (lateCancelStrike && booking.customer?.id) {
        const result = await this.applyLateCancelStrike(
          manager,
          booking.customer.id,
          booking,
        );
        strikeCount = result.strikeCount;
        instantHelpBlocked = result.instantHelpBlocked;
        compensationAmount = result.compensationAmount;
        compensationDistanceKm = result.compensationDistanceKm;
      }

      return this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_CANCELLED,
        id,
        {
          bookingId: id,
          reason: cancelReason,
          source: freeDueToNoProgress ? 'WORKER_NO_PROGRESS' : source,
          operatorId: booking.operator?.id ?? null,
          operatorName: booking.operator?.name ?? null,
          customerId: booking.customer?.id ?? null,
        },
      );
    });
    await this.outboxService.enqueueDispatch(outbox.id);

    let message =
      refundMethod === 'DIRECT'
        ? 'Booking cancelled. Payment was collected directly by the worker — please settle any refund with them.'
        : 'Booking cancelled';
    if (freeDueToNoProgress) {
      message =
        'Booking cancelled at no cost — your pro was not making progress toward you.';
    } else if (lateCancelStrike) {
      message = instantHelpBlocked
        ? `Booking cancelled. This was a late cancel (strike ${strikeCount}). Instant Help is blocked until you pay travel compensation.`
        : `Booking cancelled. Late cancel recorded (strike ${strikeCount} of ${BookingsService.LATE_CANCEL_STRIKE_THRESHOLD}).`;
    }

    return {
      status: 'CANCELLED',
      refundAmount,
      refundMethod,
      message,
      lateCancelStrike: lateCancelStrike || undefined,
      strikeCount,
      instantHelpBlocked: instantHelpBlocked || undefined,
      compensationAmount,
      compensationDistanceKm,
      workerNoProgress: freeDueToNoProgress || undefined,
    };
  }

  async requestCancel(bookingId: string, customerUserId: string, reason?: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.customer?.id !== customerUserId) {
      throw new BadRequestException('Only the customer can request cancellation');
    }
    const st = booking.status;
    if (
      st !== BookingStatus.ACCEPTED &&
      st !== BookingStatus.ARRIVED &&
      st !== BookingStatus.ACTIVE
    ) {
      throw new BadRequestException(
        'Cancel request is only available after a pro has accepted the job',
      );
    }
    if (booking.cancelRequestedAt) {
      return { cancelRequested: true, message: 'Cancel request already pending' };
    }
    booking.cancelRequestedAt = new Date();
    if (reason) booking.cancellationReason = reason;
    await this.bookingsRepository.save(booking);
    await this.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
      arrivalOtp: null,
      cancelRequested: true,
    });
    if (booking.operator?.id) {
      await this.notificationsService
        .sendToUser(booking.operator.id, {
          title: 'Cancellation requested',
          body: 'The customer asked to cancel this job. Approve or decline in the app.',
          data: { type: 'cancel_requested', bookingId: booking.id },
        })
        .catch(() => {});
    }
    return { cancelRequested: true, message: 'Cancel request sent to your pro' };
  }

  async approveCancelRequest(bookingId: string, operatorUserId: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== operatorUserId) {
      throw new BadRequestException('Only the assigned worker can approve cancellation');
    }
    if (!booking.cancelRequestedAt) {
      throw new BadRequestException('No pending cancel request');
    }
    return this.cancelBooking(
      bookingId,
      booking.cancellationReason || 'Cancelled by mutual agreement',
      'customer',
      { applyLateCancelStrike: false, skipStageGate: true },
    );
  }

  async declineCancelRequest(bookingId: string, operatorUserId: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.operator?.id !== operatorUserId) {
      throw new BadRequestException('Only the assigned worker can decline cancellation');
    }
    if (!booking.cancelRequestedAt) {
      throw new BadRequestException('No pending cancel request');
    }
    booking.cancelRequestedAt = null as any;
    await this.bookingsRepository.save(booking);
    await this.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
      arrivalOtp: null,
      cancelRequested: false,
    });
    if (booking.customer?.id) {
      await this.notificationsService
        .sendToUser(booking.customer.id, {
          title: 'Cancel declined',
          body: 'Your pro declined the cancellation — the job continues.',
          data: { type: 'cancel_declined', bookingId: booking.id },
        })
        .catch(() => {});
    }
    return { cancelRequested: false, message: 'Cancel request declined' };
  }

  async withdrawCancelRequest(bookingId: string, customerUserId: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.customer?.id !== customerUserId) {
      throw new BadRequestException('Only the customer can withdraw a cancel request');
    }
    if (!booking.cancelRequestedAt) {
      return { cancelRequested: false, message: 'No pending cancel request' };
    }
    booking.cancelRequestedAt = null as any;
    await this.bookingsRepository.save(booking);
    await this.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
      arrivalOtp: null,
      cancelRequested: false,
    });
    return { cancelRequested: false, message: 'Cancel request withdrawn' };
  }

  /** Razorpay webhook fulfilment — unlock Instant Help after compensation paid. */
  async markLateCancelCompensationPaid(customerUserId: string): Promise<void> {
    const users = this.dataSource.getRepository(User);
    const user = await users.findOne({ where: { id: customerUserId } });
    if (!user) throw new NotFoundException('User not found');
    if (!user.instantHelpBlocked) return;

    const bookingId = user.unblockCompensationBookingId;
    const amount = user.unblockCompensationAmountInr ?? 0;
    const distanceKm = user.unblockCompensationDistanceKm;

    user.instantHelpBlocked = false;
    user.lateCancelStrikeCount = 0;
    user.unblockCompensationBookingId = null;
    user.unblockCompensationAmountInr = null;
    user.unblockCompensationDistanceKm = null;
    await users.save(user);

    let workerId: string | null = null;
    if (bookingId) {
      const booking = await this.bookingsRepository.findOne({
        where: { id: bookingId },
        relations: ['operator'],
      });
      if (booking) {
        booking.lateCancelCompensationPaidAt = new Date();
        booking.lateCancelCompensationAmountInr = amount;
        if (distanceKm != null) {
          booking.lateCancelCompensationDistanceKm = Number(distanceKm);
        }
        await this.bookingsRepository.save(booking);
        workerId = booking.operator?.id ?? null;
      }
    }

    if (workerId) {
      await this.notificationsService
        .sendToUser(workerId, {
          title: 'Travel compensation received',
          body: `A customer paid ₹${amount} travel compensation for a late-cancelled job.`,
          data: {
            type: 'late_cancel_compensation_paid',
            bookingId: bookingId ?? '',
            amount: String(amount),
          },
        })
        .catch(() => {});
    }
  }

  getLateCancelCompensationQuote(userId: string): Promise<{
    blocked: boolean;
    amountInr: number | null;
    distanceKm: number | null;
    bookingId: string | null;
    workerName: string | null;
  }> {
    return this.dataSource
      .getRepository(User)
      .findOne({ where: { id: userId } })
      .then(async (user) => {
        if (!user || !user.instantHelpBlocked) {
          return {
            blocked: false,
            amountInr: null,
            distanceKm: null,
            bookingId: null,
            workerName: null,
          };
        }
        let workerName: string | null = null;
        if (user.unblockCompensationBookingId) {
          const b = await this.bookingsRepository.findOne({
            where: { id: user.unblockCompensationBookingId },
            relations: ['operator'],
          });
          workerName = b?.operator?.name ?? null;
        }
        return {
          blocked: true,
          amountInr: user.unblockCompensationAmountInr,
          distanceKm:
            user.unblockCompensationDistanceKm != null
              ? Number(user.unblockCompensationDistanceKm)
              : null,
          bookingId: user.unblockCompensationBookingId,
          workerName,
        };
      });
  }

  private async assertInstantHelpAllowed(customerId: string): Promise<void> {
    const user = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: customerId } });
    if (user?.instantHelpBlocked) {
      const amt = user.unblockCompensationAmountInr ?? 0;
      const km = user.unblockCompensationDistanceKm;
      const kmPart =
        km != null && Number(km) > 0
          ? ` (${Number(km).toFixed(1)} km travel)`
          : '';
      throw new BadRequestException(
        `Instant Help is blocked after repeated late cancels. Pay ₹${amt} travel compensation${kmPart} to unlock.`,
      );
    }
  }

  private isWithinCancelGrace(booking: Booking): boolean {
    const acceptedAt = booking.acceptedAt
      ? new Date(booking.acceptedAt).getTime()
      : null;
    // Legacy rows without acceptedAt: treat as still in grace (one free cancel).
    if (!acceptedAt) return true;
    const graceMs = BookingsService.CANCEL_GRACE_MINUTES * 60 * 1000;
    return Date.now() - acceptedAt <= graceMs;
  }

  private async applyLateCancelStrike(
    manager: any,
    customerId: string,
    booking: Booking,
  ): Promise<{
    strikeCount: number;
    instantHelpBlocked: boolean;
    compensationAmount: number | null;
    compensationDistanceKm: number | null;
  }> {
    const users = manager.getRepository(User);
    const user = await users.findOne({ where: { id: customerId } });
    if (!user) {
      return {
        strikeCount: 0,
        instantHelpBlocked: false,
        compensationAmount: null,
        compensationDistanceKm: null,
      };
    }

    user.lateCancelStrikeCount = (user.lateCancelStrikeCount || 0) + 1;
    let compensationAmount: number | null = null;
    let compensationDistanceKm: number | null = null;

    if (
      user.lateCancelStrikeCount >= BookingsService.LATE_CANCEL_STRIKE_THRESHOLD
    ) {
      const comp = await this.computeDistanceCompensation(booking);
      user.instantHelpBlocked = true;
      user.unblockCompensationBookingId = booking.id;
      user.unblockCompensationAmountInr = comp.amountInr;
      user.unblockCompensationDistanceKm = comp.distanceKm;
      compensationAmount = comp.amountInr;
      compensationDistanceKm = comp.distanceKm;

      booking.lateCancelCompensationAmountInr = comp.amountInr;
      booking.lateCancelCompensationDistanceKm = comp.distanceKm;
      await manager.save(booking);

      await this.notificationsService
        .sendToUser(customerId, {
          title: 'Instant Help blocked',
          body: `Pay ₹${comp.amountInr} travel compensation to unlock Instant Help.`,
          data: { type: 'instant_help_blocked', bookingId: booking.id },
        })
        .catch(() => {});
    }

    await users.save(user);
    return {
      strikeCount: user.lateCancelStrikeCount,
      instantHelpBlocked: !!user.instantHelpBlocked,
      compensationAmount,
      compensationDistanceKm,
    };
  }

  private async computeDistanceCompensation(booking: Booking): Promise<{
    amountInr: number;
    distanceKm: number;
  }> {
    const perKm = await this.masterEntriesService.getConfigNumber(
      'late_cancel_compensation_per_km',
      BookingsService.COMP_PER_KM_DEFAULT,
    );
    const minInr = await this.masterEntriesService.getConfigNumber(
      'late_cancel_compensation_min_inr',
      BookingsService.COMP_MIN_INR_DEFAULT,
    );
    const maxInr = await this.masterEntriesService.getConfigNumber(
      'late_cancel_compensation_max_inr',
      BookingsService.COMP_MAX_INR_DEFAULT,
    );

    const jobLat = Number(booking.serviceLat);
    const jobLng = Number(booking.serviceLng);
    let workerLat: number | null = null;
    let workerLng: number | null = null;

    const operatorId = booking.operator?.id;
    if (operatorId) {
      const loc = await this.redisService.getWorkerLocation(operatorId);
      if (loc && Number.isFinite(loc.lat) && Number.isFinite(loc.lng)) {
        workerLat = Number(loc.lat);
        workerLng = Number(loc.lng);
      } else {
        const profile = await this.workerProfileRepo.findOne({
          where: { user: { id: operatorId } },
        });
        if (profile?.lastLat != null && profile?.lastLng != null) {
          workerLat = Number(profile.lastLat);
          workerLng = Number(profile.lastLng);
        }
      }
    }

    let distanceKm = 0;
    if (
      Number.isFinite(jobLat) &&
      Number.isFinite(jobLng) &&
      workerLat != null &&
      workerLng != null &&
      Number.isFinite(workerLat) &&
      Number.isFinite(workerLng)
    ) {
      distanceKm = this.calculateDistance(workerLat, workerLng, jobLat, jobLng);
    }

    const raw = Math.round(distanceKm * perKm);
    const amountInr = Math.min(maxInr, Math.max(minInr, raw || minInr));
    return {
      amountInr,
      distanceKm: Math.round(distanceKm * 100) / 100,
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
      for (const stale of bookings.filter(
        (b) => b.status !== BookingStatus.REQUESTED,
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
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.arrivalOtp || booking.arrivalOtp !== otp) {
      throw new BadRequestException('Invalid arrival OTP');
    }

    this.redisService
      .deleteOtp(`otp:booking:${bookingId}:arrival`)
      .catch(() => {});

    booking.status = BookingStatus.ACTIVE;
    booking.startedAt = new Date();
    await this.bookingsRepository.save(booking);

    await this.cacheAndEmitBookingStatus(bookingId, {
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
              BookingsService.INSTANT_PETROL_PER_KM_DEFAULT,
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
        locked.type === BookingType.INSTANT ? configuredPetrolRate : 0;
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
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
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

    const txResult = await this.dataSource.transaction(async (manager) => {
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
      return { outboxId: outbox.id };
    });

    await this.outboxService.enqueueDispatch(txResult.outboxId);

    return {
      message: booking.isPaid
        ? 'Booking marked as paid.'
        : 'Payment confirmation recorded. Waiting for the other party.',
      isPaid: !!booking.isPaid,
      workerPaidConfirmed: !!booking.workerPaidConfirmed,
      customerPaidConfirmed: !!booking.customerPaidConfirmed,
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

  /**
   * Caches the booking status in Redis AND instantly pushes a real-time
   * 'booking_status_update' event over Socket.IO to both customer and worker.
   * This allows clients to update their UI in ~10ms while keeping the 30s poll
   * interval as a relaxed fallback.
   */
  async cacheAndEmitBookingStatus(
    bookingId: string,
    payload: Record<string, any>,
  ): Promise<void> {
    await this.redisService
      .cacheBookingStatus(bookingId, payload)
      .catch(() => {});

    const status = String(payload.status || '').toUpperCase();
    if (payload.customerId) {
      try {
        this.messagesGateway.emitUserEvent(
          payload.customerId,
          'booking_status_update',
          {
            ...payload,
            bookingId,
            id: bookingId,
            arrivalOtp: status === 'ACCEPTED' ? payload.arrivalOtp : null,
          },
        );
      } catch (e) {
        this.logger.error(
          `Socket emit booking_status_update (customer) failed: ${(e as Error)?.message}`,
        );
      }
    }
    if (payload.operatorId) {
      try {
        this.messagesGateway.emitUserEvent(
          payload.operatorId,
          'booking_status_update',
          {
            ...payload,
            bookingId,
            id: bookingId,
            arrivalOtp: null, // worker never receives arrivalOtp in status payload
          },
        );
      } catch (e) {
        this.logger.error(
          `Socket emit booking_status_update (worker) failed: ${(e as Error)?.message}`,
        );
      }
    }
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

  /**
   * Status poll used by the app. Prefers Redis (written on every transition)
   * so the shared fallback poll does not hit Postgres on every tick. Falls back
   * to DB and refreshes the cache when Redis is cold / unauthorized.
   */
  async getStatusForParticipant(
    bookingId: string,
    userId: string,
  ): Promise<{
    status: string;
    operatorName: string | null;
    operatorId: string | null;
    arrivalOtp: string | null;
    cancelRequested: boolean;
    workerNoProgress?: boolean;
    isPaid: boolean;
    workerPaidConfirmed: boolean;
    customerPaidConfirmed: boolean;
    /** Live worker GPS from Redis — for customer map poll fallback. */
    operatorLat: number | null;
    operatorLng: number | null;
  }> {
    const trackingStatuses = new Set([
      'ACCEPTED',
      'ARRIVED',
      'ACTIVE',
      'IN_PROGRESS',
    ]);

    const attachOperatorLocation = async (
      operatorId: string | null | undefined,
      status: string,
    ): Promise<{ operatorLat: number | null; operatorLng: number | null }> => {
      if (!operatorId || !trackingStatuses.has(status)) {
        return { operatorLat: null, operatorLng: null };
      }
      try {
        const loc = await this.redisService.getWorkerLocation(operatorId);
        if (
          loc &&
          typeof loc.lat === 'number' &&
          typeof loc.lng === 'number' &&
          Number.isFinite(loc.lat) &&
          Number.isFinite(loc.lng)
        ) {
          return { operatorLat: loc.lat, operatorLng: loc.lng };
        }
      } catch {
        // Redis miss/error — socket path remains primary.
      }
      return { operatorLat: null, operatorLng: null };
    };

    const cached = await this.redisService.getCachedBookingStatus(bookingId);
    if (
      cached &&
      (cached.customerId === userId || cached.operatorId === userId)
    ) {
      const isCustomer = cached.customerId === userId;
      const status = String(cached.status || '').toUpperCase();
      const loc = await attachOperatorLocation(cached.operatorId, status);
      return {
        status,
        operatorName: cached.operatorName ?? null,
        operatorId: cached.operatorId ?? null,
        arrivalOtp:
          isCustomer && status === 'ACCEPTED'
            ? (cached.arrivalOtp ?? null)
            : null,
        cancelRequested: !!cached.cancelRequested,
        workerNoProgress: !!cached.workerNoProgress,
        isPaid: !!cached.isPaid,
        workerPaidConfirmed: !!cached.workerPaidConfirmed,
        customerPaidConfirmed: !!cached.customerPaidConfirmed,
        operatorLat: loc.operatorLat,
        operatorLng: loc.operatorLng,
      };
    }

    const booking = await this.getBookingById(bookingId);
    if (!booking) throw new NotFoundException('Booking not found');
    const isCustomer = booking.customer?.id === userId;
    const isOperator = booking.operator?.id === userId;
    if (!isCustomer && !isOperator) {
      throw new NotFoundException('Booking not found');
    }

    const payload = {
      status: booking.status,
      operatorName: booking.operator?.name ?? null,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
      arrivalOtp: booking.arrivalOtp,
      cancelRequested: !!booking.cancelRequestedAt,
      workerNoProgress: !!booking.workerNoProgressAt,
      isPaid: !!booking.isPaid,
      workerPaidConfirmed: !!booking.workerPaidConfirmed,
      customerPaidConfirmed: !!booking.customerPaidConfirmed,
    };
    await this.redisService
      .cacheBookingStatus(bookingId, payload)
      .catch(() => {});

    const status = String(booking.status);
    const loc = await attachOperatorLocation(
      payload.operatorId,
      status.toUpperCase(),
    );
    return {
      status,
      operatorName: payload.operatorName,
      operatorId: payload.operatorId,
      arrivalOtp:
        isCustomer && booking.status === BookingStatus.ACCEPTED
          ? booking.arrivalOtp
          : null,
      cancelRequested: payload.cancelRequested,
      workerNoProgress: payload.workerNoProgress,
      isPaid: payload.isPaid,
      workerPaidConfirmed: payload.workerPaidConfirmed,
      customerPaidConfirmed: payload.customerPaidConfirmed,
      operatorLat: loc.operatorLat,
      operatorLng: loc.operatorLng,
    };
  }

  /// SECURITY FIX: shared guard for the booking mutation endpoints that used
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

  /**
   * True when the worker has fresh GPS and is either near the job or has
   * closed meaningful distance since accept. Used by the Bull progress job.
   */
  evaluateWorkerProgress(
    booking: {
      serviceLat?: number | string | null;
      serviceLng?: number | string | null;
      acceptDistanceKm?: number | string | null;
    },
    location: { lat: number; lng: number; timestamp?: string } | null,
    nowMs: number = Date.now(),
  ): { progressing: boolean; reason: string; distanceKm?: number } {
    if (!location || !Number.isFinite(location.lat) || !Number.isFinite(location.lng)) {
      return { progressing: false, reason: 'No recent location update found.' };
    }

    if (location.timestamp) {
      const age = nowMs - new Date(location.timestamp).getTime();
      if (!Number.isFinite(age) || age > BookingsService.GPS_LOCATION_MAX_AGE_MS) {
        return {
          progressing: false,
          reason: 'Location update is stale (GPS not fresh).',
        };
      }
    }

    const jobLat = Number(booking.serviceLat);
    const jobLng = Number(booking.serviceLng);
    if (!Number.isFinite(jobLat) || !Number.isFinite(jobLng)) {
      return { progressing: true, reason: 'No job coordinates — skip check.' };
    }

    const distanceKm = this.calculateDistance(
      location.lat,
      location.lng,
      jobLat,
      jobLng,
    );

    if (distanceKm <= BookingsService.PROGRESS_NEAR_JOB_KM) {
      return {
        progressing: true,
        reason: `Worker is near the job (${distanceKm.toFixed(2)} km).`,
        distanceKm,
      };
    }

    const acceptDist =
      booking.acceptDistanceKm != null
        ? Number(booking.acceptDistanceKm)
        : NaN;
    if (Number.isFinite(acceptDist)) {
      const closerBy = acceptDist - distanceKm;
      if (closerBy >= BookingsService.PROGRESS_MIN_CLOSER_KM) {
        return {
          progressing: true,
          reason: `Worker moved ${closerBy.toFixed(2)} km closer.`,
          distanceKm,
        };
      }
      return {
        progressing: false,
        reason: `Worker has not progressed (only ${closerBy.toFixed(2)} km closer; still ${distanceKm.toFixed(2)} km away).`,
        distanceKm,
      };
    }

    // Legacy bookings without an accept snapshot: keep the old 5 km rule.
    if (distanceKm <= 5) {
      return {
        progressing: true,
        reason: `Within 5 km (legacy, no accept baseline).`,
        distanceKm,
      };
    }
    return {
      progressing: false,
      reason: `Worker is too far (${distanceKm.toFixed(2)} km) without accept baseline.`,
      distanceKm,
    };
  }

  /**
   * Records a progress/GPS violation while the booking is ACCEPTED.
   * 1st: warn worker and allow a 3-minute recheck.
   * 2nd: flag workerNoProgressAt so the customer can cancel free; record a
   *      worker profile strike. Does not auto-cancel the booking.
   */
  async addGpsStrike(bookingId: string): Promise<
    | {
        cancelled: boolean;
        strikes: number;
        freeCancelEnabled?: boolean;
      }
    | undefined
  > {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) return;
    if (booking.status !== BookingStatus.ACCEPTED) return;

    if (booking.workerNoProgressAt) {
      return {
        cancelled: false,
        strikes: booking.gpsStrikes,
        freeCancelEnabled: true,
      };
    }

    booking.gpsStrikes += 1;

    if (booking.gpsStrikes >= BookingsService.PROGRESS_STRIKE_THRESHOLD) {
      booking.workerNoProgressAt = new Date();
      await this.bookingsRepository.save(booking);

      await this.cacheAndEmitBookingStatus(bookingId, {
        status: booking.status,
        operatorName: booking.operator?.name,
        operatorId: booking.operator?.id ?? null,
        customerId: booking.customer?.id ?? null,
        workerNoProgress: true,
      });

      if (booking.customer?.id) {
        await this.notificationsService.sendToUser(booking.customer.id, {
          title: 'Pro not moving',
          body: 'Your pro does not appear to be heading your way. You can cancel this booking at no cost.',
          data: {
            type: 'worker_no_progress',
            bookingId,
          },
        });
      }
      if (booking.operator?.id) {
        await this.notificationsService.sendToUser(booking.operator.id, {
          title: 'No progress detected',
          body: 'GPS shows you have not moved toward the customer. They can now cancel free, and a strike was recorded.',
          data: { type: 'worker_no_progress', bookingId },
        });

        await this.workersService
          .recordStrike(booking.operator.id, {
            type: WorkerStrikeType.GPS_FORFEIT,
            bookingId,
            reason: `A ${booking.skill || 'service'} job showed no GPS progress toward the customer; customer may cancel free.`,
          })
          .catch((e) =>
            this.logger.error(
              `[GpsStrike] recordStrike failed for ${bookingId}: ${e?.message ?? e}`,
            ),
          );
      }

      return {
        cancelled: false,
        strikes: booking.gpsStrikes,
        freeCancelEnabled: true,
      };
    }

    await this.bookingsRepository.save(booking);

    if (booking.operator?.id) {
      await this.notificationsService.notifyGpsStrike(
        booking.operator.id,
        booking.gpsStrikes,
      );
    }

    return { cancelled: false, strikes: booking.gpsStrikes };
  }

  /**
   * Helper to calculate distance between two coordinates in km using Haversine formula
   */
  public calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
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
