import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, In, Repository } from 'typeorm';
import { JobCreditsService } from '../billing/job-credits.service';
import { NotificationsService } from '../notifications/notifications.service';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { RedisService } from '../redis/redis.service';
import { WorkersService } from '../workers/workers.service';
import { Booking, BookingStatus } from './booking.entity';
import { BookingStatusService } from './booking-status.service';

@Injectable()
export class BookingClaimService {
  constructor(
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
    private readonly workersService: WorkersService,
    private readonly dataSource: DataSource,
    private readonly outboxService: OutboxService,
    private readonly jobCreditsService: JobCreditsService,
    private readonly bookingStatusService: BookingStatusService,
  ) {}

  private calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
    const radiusKm = 6371;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    return radiusKm * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  async acceptBooking(
    bookingId: string,
    workerId: string,
  ): Promise<{ message: string; status: string; booking: any }> {
    console.log(
      `[AcceptBooking] START — bookingId=${bookingId}, workerId=${workerId}`,
    );

    let savedBooking: Booking;
    let operatorName: string | null = null;

    try {
      const txResult = await this.dataSource.transaction(async (manager) => {
        console.log('[AcceptBooking] Inside transaction — locking booking row');
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

        const booking = await manager.findOne(Booking, {
          where: { id: bookingId },
          relations: ['customer', 'operator'],
        });
        if (!booking) throw new NotFoundException('Booking not found');

        // Broadcast Instant Help: only notified / pending workers may claim.
        if (!booking.operator) {
          const pendingIds =
            await this.redisService.getPendingBookingIds(workerId);
          const notified = await this.getNotifiedWorkerIds(bookingId);
          if (!pendingIds.includes(bookingId) && !notified.includes(workerId)) {
            throw new BadRequestException(
              'You are not eligible to accept this booking.',
            );
          }
        }

        const remainingCredits = await this.jobCreditsService.consumeCredit(
          workerId,
          bookingId,
          manager,
        );
        if (remainingCredits === 0) {
          await this.workersService.forceOffline(workerId);
          this.notificationsService.sendToUser(workerId, {
            title: 'Out of credits',
            body: 'You have been taken offline because you have no job credits left. Buy a pack to receive new jobs.',
            data: { type: 'out_of_credits' },
          });
        }

        if (!booking.operator) {
          booking.operator = { id: workerId } as any;
        } else if (booking.operator.id !== workerId) {
          throw new BadRequestException(
            'You are not assigned to this booking.',
          );
        }

        booking.status = BookingStatus.ACCEPTED;
        booking.acceptedAt = new Date();

        const acceptLocation =
          await this.redisService.getWorkerLocation(workerId);
        if (
          acceptLocation &&
          Number.isFinite(acceptLocation.lat) &&
          Number.isFinite(acceptLocation.lng)
        ) {
          booking.acceptLat = Number(acceptLocation.lat);
          booking.acceptLng = Number(acceptLocation.lng);
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
        const saved =
          (await manager.findOne(Booking, {
            where: { id: bookingId },
            relations: ['customer', 'operator'],
          })) ?? booking;

        const otherPending = await manager.find(Booking, {
          where: {
            operator: { id: workerId },
            status: BookingStatus.REQUESTED,
          },
          relations: ['customer'],
        });
        const filtered = otherPending.filter(
          (pending) => pending.id !== bookingId,
        );
        if (filtered.length > 0) {
          await manager.update(
            Booking,
            { id: In(filtered.map((pending) => pending.id)) },
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
            cancelledBookingIds: filtered.map((pending) => pending.id),
            cancelledCustomerIds: filtered
              .map((pending) => pending.customer?.id)
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

    // Publish ACCEPTED to Redis + sockets immediately. The outbox handler
    // also does this (FCM, busy flag, queues), but customer status polls hit
    // Redis first — leaving REQUESTED until Bull runs kept the search UI
    // up and still cancelable after the worker had already accepted.
    const customerId = savedBooking.customer?.id ?? null;
    await this.bookingStatusService
      .cacheAndEmitBookingStatus(bookingId, {
        status: 'ACCEPTED',
        operatorName,
        operatorId: workerId,
        customerId,
        arrivalOtp: savedBooking.arrivalOtp,
      })
      .catch((e) =>
        console.error(
          '[AcceptBooking] immediate status publish failed:',
          e?.message ?? e,
        ),
      );

    // Mark busy inline so Instant Help targeting stops offering this worker
    // before the outbox onAccepted handler runs.
    try {
      await this.workersService.setWorkerStatus(workerId, 'busy');
    } catch (e) {
      console.error(
        '[AcceptBooking] setWorkerStatus(busy) failed:',
        (e as Error)?.message ?? e,
      );
    }

    return {
      message: 'Booking accepted. Head to the service location now.',
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
    const notified = await this.getNotifiedWorkerIds(bookingId);
    if (
      !isAssignedOperator &&
      !pendingIds.includes(bookingId) &&
      !notified.includes(workerId)
    ) {
      throw new NotFoundException('Booking not found');
    }

    await this.redisService.removePendingBooking(workerId, bookingId);
    await this.dropWorkerFromNotified(bookingId, workerId, notified);

    if (booking.customer?.id && booking.skill) {
      await this.redisService.markWorkerRejectedJob(
        booking.customer.id,
        booking.skill,
        workerId,
      );
    }

    if (isAssignedOperator) {
      booking.status = BookingStatus.REJECTED;
      await this.bookingsRepository.save(booking);
      await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
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
    notified: string[],
  ): Promise<void> {
    if (notified.length === 0) return;
    const remaining = notified.filter((id) => id !== workerId);
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
    } catch (error) {
      console.error(
        `[RejectBooking] notified update failed for ${bookingId}:`,
        error,
      );
    }
  }
}
