import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { Booking, BookingStatus } from './booking.entity';
import { User } from '../users/user.entity';
import { WalletsService } from '../wallets/wallets.service';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { JobCreditsService } from '../billing/job-credits.service';
import { CreditTransactionReason } from '../billing/credit-transaction.entity';
import { MasterEntriesService } from '../master-entries/master-entries.service';
import { BookingStatusService } from './booking-status.service';

@Injectable()
export class BookingCancelService {
  /** Free unilateral cancel for this many minutes after ACCEPTED. */
  private static readonly CANCEL_GRACE_MINUTES = 3;
  private static readonly LATE_CANCEL_STRIKE_THRESHOLD = 3;
  private static readonly COMP_PER_KM_DEFAULT = 10;
  private static readonly COMP_MIN_INR_DEFAULT = 49;
  private static readonly COMP_MAX_INR_DEFAULT = 299;

  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    @InjectRepository(WorkerProfile)
    private workerProfileRepo: Repository<WorkerProfile>,
    private walletsService: WalletsService,
    private notificationsService: NotificationsService,
    private redisService: RedisService,
    private dataSource: DataSource,
    private outboxService: OutboxService,
    private jobCreditsService: JobCreditsService,
    private masterEntriesService: MasterEntriesService,
    private bookingStatusService: BookingStatusService,
  ) {}

  /**
   * Timeout path for unmatched REQUESTED bookings. Accept and timeout race
   * on a conditional UPDATE … WHERE status='REQUESTED' in the same
   * transaction as the outbox append: whichever commits first wins; the
   * loser is a clean no-op.
   */
  async timeoutCancelBooking(
    bookingId: string,
  ): Promise<{ cancelled: boolean }> {
    let outboxId: string | null = null;
    let customerId: string | null = null;
    let operatorId: string | null = null;
    let operatorName: string | null = null;
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
      customerId = booking?.customer?.id ?? null;
      operatorId = booking?.operator?.id ?? null;
      operatorName = booking?.operator?.name ?? null;
      const outbox = await this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_CANCELLED,
        bookingId,
        {
          bookingId,
          reason: 'No worker accepted in time',
          source: 'timeout',
          operatorId,
          operatorName,
          customerId,
        },
      );
      outboxId = outbox.id;
      return true;
    });
    if (outboxId) {
      await this.outboxService.enqueueDispatch(outboxId);
      await this.bookingStatusService
        .cacheAndEmitBookingStatus(bookingId, {
          status: 'CANCELLED',
          operatorName,
          operatorId,
          customerId,
          cancelRequested: false,
        })
        .catch(() => undefined);
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
   *
   * Accept races: the row is locked in-tx. A cancel that started while
   * REQUESTED fails cleanly if accept already committed ACCEPTED+.
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
    const initial = await this.bookingsRepository.findOne({
      where: { id },
      relations: ['customer', 'operator'],
    });
    if (!initial) throw new NotFoundException('Booking not found');
    if (initial.status === BookingStatus.COMPLETED) {
      throw new BadRequestException('Completed bookings cannot be cancelled.');
    }

    const matchingStatuses = new Set([
      BookingStatus.REQUESTED,
      BookingStatus.PENDING,
      BookingStatus.CUSTOM_REQUESTED,
    ]);
    const startedAsMatch = matchingStatuses.has(initial.status);

    let lateCancelStrike = false;
    let strikeCount: number | undefined;
    let instantHelpBlocked = false;
    let compensationAmount: number | null = null;
    let compensationDistanceKm: number | null = null;
    let freeDueToNoProgress = false;
    let refundAmount = 0;
    let refundMethod = 'NONE';
    let cancelReason = reason;
    let operatorId: string | null = null;
    let operatorName: string | null = null;
    let customerId: string | null = null;
    let outboxSource: string = source;

    const outbox = await this.dataSource.transaction(async (manager) => {
      // Postgres rejects FOR UPDATE on the nullable side of an outer join, so
      // the row is locked bare and then re-read with its relations.
      const lockedRow = await manager
        .createQueryBuilder(Booking, 'booking')
        .setLock('pessimistic_write')
        .where('booking.id = :id', { id })
        .getOne();
      if (!lockedRow) throw new NotFoundException('Booking not found');

      const locked = await manager.findOne(Booking, {
        where: { id },
        relations: ['customer', 'operator'],
      });
      if (!locked) throw new NotFoundException('Booking not found');
      if (locked.status === BookingStatus.COMPLETED) {
        throw new BadRequestException('Completed bookings cannot be cancelled.');
      }
      if (locked.status === BookingStatus.CANCELLED) {
        throw new BadRequestException('Booking is already cancelled.');
      }

      // Search-cancel lost the race to accept — do not silently cancel live job.
      if (
        source === 'customer' &&
        !opts?.skipStageGate &&
        startedAsMatch &&
        !matchingStatuses.has(locked.status)
      ) {
        throw new BadRequestException(
          'This request was already accepted. Refresh to continue or cancel the accepted job.',
        );
      }

      freeDueToNoProgress =
        source === 'customer' &&
        !!locked.workerNoProgressAt &&
        locked.status === BookingStatus.ACCEPTED;

      const applyStrike =
        source === 'customer' &&
        opts?.applyLateCancelStrike !== false &&
        !freeDueToNoProgress;

      if (source === 'customer' && !opts?.skipStageGate) {
        const st = locked.status;
        if (st === BookingStatus.ARRIVED || st === BookingStatus.ACTIVE) {
          throw new BadRequestException(
            'This job has already started or the pro has arrived. Ask your pro to approve a cancellation instead.',
          );
        }
        if (
          st === BookingStatus.ACCEPTED &&
          !freeDueToNoProgress &&
          !this.isWithinCancelGrace(locked)
        ) {
          lateCancelStrike = applyStrike;
        }
      }

      cancelReason = freeDueToNoProgress
        ? `${reason} [WORKER_NO_PROGRESS]`
        : reason;
      outboxSource = freeDueToNoProgress ? 'WORKER_NO_PROGRESS' : source;

      // Refund policy: refund only money Gixbee actually captured.
      if (locked.isPaid && locked.customer?.id) {
        const paidAmount = Number(locked.totalAmount ?? locked.amount) || 0;
        if (paidAmount > 0) {
          if (locked.paymentMethod === 'WALLET' && locked.operator?.id) {
            await this.walletsService.reverseBookingTransfer(
              locked.customer.id,
              locked.operator.id,
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
        !!locked.operator?.id &&
        opts?.refundJobCredit !== false &&
        !freeDueToNoProgress;

      locked.status = BookingStatus.CANCELLED;
      locked.cancellationReason = cancelReason;
      locked.cancelRequestedAt = null as any;
      await manager.save(locked);

      if (shouldRefundCredit && locked.operator?.id) {
        console.log(
          `[CancelBooking] Refunding job credit(s) to worker ${locked.operator.id} due to customer cancellation`,
        );
        await this.jobCreditsService.refundCredit(
          locked.operator.id,
          id,
          CreditTransactionReason.REFUND_CUSTOMER_CANCEL,
          manager,
        );
      }

      if (lateCancelStrike && locked.customer?.id) {
        const result = await this.applyLateCancelStrike(
          manager,
          locked.customer.id,
          locked,
        );
        strikeCount = result.strikeCount;
        instantHelpBlocked = result.instantHelpBlocked;
        compensationAmount = result.compensationAmount;
        compensationDistanceKm = result.compensationDistanceKm;
      }

      operatorId = locked.operator?.id ?? null;
      operatorName = locked.operator?.name ?? null;
      customerId = locked.customer?.id ?? null;

      return this.outboxService.append(
        manager,
        OutboxEventType.BOOKING_CANCELLED,
        id,
        {
          bookingId: id,
          reason: cancelReason,
          source: outboxSource,
          operatorId,
          operatorName,
          customerId,
        },
      );
    });
    await this.outboxService.enqueueDispatch(outbox.id);

    // Immediate Redis + socket — do not wait for outbox (accept path parity).
    await this.bookingStatusService
      .cacheAndEmitBookingStatus(id, {
        status: 'CANCELLED',
        operatorName,
        operatorId,
        customerId,
        cancelRequested: false,
      })
      .catch(() => undefined);

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
        : `Booking cancelled. Late cancel recorded (strike ${strikeCount} of ${BookingCancelService.LATE_CANCEL_STRIKE_THRESHOLD}).`;
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
    await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
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
    await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
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
    await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
      status: booking.status,
      operatorName: booking.operator?.name,
      operatorId: booking.operator?.id ?? null,
      customerId: booking.customer?.id ?? null,
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

  private isWithinCancelGrace(booking: Booking): boolean {
    const acceptedAt = booking.acceptedAt
      ? new Date(booking.acceptedAt).getTime()
      : null;
    // Legacy rows without acceptedAt: treat as still in grace (one free cancel).
    if (!acceptedAt) return true;
    const graceMs = BookingCancelService.CANCEL_GRACE_MINUTES * 60 * 1000;
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
      user.lateCancelStrikeCount >= BookingCancelService.LATE_CANCEL_STRIKE_THRESHOLD
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
      BookingCancelService.COMP_PER_KM_DEFAULT,
    );
    const minInr = await this.masterEntriesService.getConfigNumber(
      'late_cancel_compensation_min_inr',
      BookingCancelService.COMP_MIN_INR_DEFAULT,
    );
    const maxInr = await this.masterEntriesService.getConfigNumber(
      'late_cancel_compensation_max_inr',
      BookingCancelService.COMP_MAX_INR_DEFAULT,
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

  /**
   * Helper to calculate distance between two coordinates in km using Haversine formula
   */
  private calculateDistance(
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
