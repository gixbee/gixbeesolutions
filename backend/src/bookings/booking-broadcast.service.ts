import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { DataSource } from 'typeorm';
import { DEFAULT_BOOKING_PAYMENT_METHOD } from '../common/money-model';
import { MessagesGateway } from '../messages/messages.gateway';
import { NotificationsService } from '../notifications/notifications.service';
import { OutboxService } from '../outbox/outbox.service';
import { OutboxEventType } from '../outbox/outbox.types';
import { RedisService } from '../redis/redis.service';
import { User } from '../users/user.entity';
import {
  REBROADCAST_RADIUS_STRETCH,
  WorkersService,
} from '../workers/workers.service';
import { Booking, BookingStatus, BookingType } from './booking.entity';
import { selectBroadcastTargets } from './booking-dispatch-targeting';
import { BookingStatusService } from './booking-status.service';

export interface CreateBroadcastBookingData {
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
}

@Injectable()
export class BookingBroadcastService {
  private readonly logger = new Logger(BookingBroadcastService.name);

  constructor(
    @InjectQueue('bookings') private readonly bookingsQueue: Queue,
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
    private readonly workersService: WorkersService,
    private readonly dataSource: DataSource,
    private readonly messagesGateway: MessagesGateway,
    private readonly outboxService: OutboxService,
    private readonly bookingStatusService: BookingStatusService,
  ) {}

  private generateOtp(): string {
    return Math.floor(1000 + Math.random() * 9000).toString();
  }

  async createBroadcastBooking(
    customerId: string,
    data: CreateBroadcastBookingData,
  ): Promise<{ booking: Booking; notified: number }> {
    const nearby = await this.workersService.getNearby(
      customerId,
      data.skill,
      data.serviceLat,
      data.serviceLng,
    );
    const targets = selectBroadcastTargets(nearby, data.preferredLanguages);
    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();

    const customer = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: customerId }, select: ['id', 'name'] })
      .catch(() => null);
    const customerFirstName =
      customer?.name?.trim().split(/\s+/)[0] || undefined;
    const notifiedWorkerIds = targets.map((worker) => worker.id);

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
            notifiedAt: new Date().toISOString(),
            arrivalOtp,
            completionOtp,
            notifiedWorkerIds,
            attempt: 1,
          },
        );
        return { savedBooking: saved, outboxId: outbox.id };
      },
    );

    // Publish the open request inline, the same way the targeted create does,
    // then let the outbox own the pro-side push/socket fan-out. Without this
    // there is a window between commit and the outbox worker where the
    // customer's status poll finds no cached state and `GET bookings/pending`
    // shows the pros nothing. Both writes are idempotent: the status cache
    // merges and the pending queue is a sorted-set add, so the handler
    // repeating them a moment later is a no-op.
    await this.bookingStatusService
      .cacheAndEmitBookingStatus(savedBooking.id, {
        status: 'REQUESTED',
        operatorName: null,
        operatorId: null,
        customerId,
        arrivalOtp,
      })
      .catch((e) =>
        this.logger.error(
          `inline status publish failed for ${savedBooking.id}: ${
            (e as Error)?.message ?? e
          }`,
        ),
      );
    await Promise.all(
      notifiedWorkerIds.map((workerId) =>
        this.redisService
          .addPendingBooking(workerId, savedBooking.id)
          .catch((e) =>
            this.logger.error(
              `inline pending add ${workerId} failed: ${
                (e as Error)?.message ?? e
              }`,
            ),
          ),
      ),
    );

    await this.outboxService.enqueueDispatch(outboxId);
    console.log(
      `[BroadcastBooking] ${savedBooking.id} queued fan-out to ${notifiedWorkerIds.length} pros for ${data.skill}`,
    );
    return { booking: savedBooking, notified: notifiedWorkerIds.length };
  }

  async rebroadcastBooking(
    bookingId: string,
  ): Promise<{ stillOpen: boolean; notified: number }> {
    const booking = await this.bookingStatusService.getBookingById(bookingId);
    if (
      !booking ||
      booking.status !== BookingStatus.REQUESTED ||
      booking.operator ||
      booking.type !== BookingType.INSTANT
    ) {
      return { stillOpen: false, notified: 0 };
    }

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
    const fresh = selectBroadcastTargets(
      nearby.filter((worker) => !alreadyNotified.has(worker.id)),
      booking.preferredLanguages,
    );
    const freshIds = fresh.map((worker) => worker.id);

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
          notifiedAt: new Date().toISOString(),
          arrivalOtp: booking.arrivalOtp,
          completionOtp: booking.completionOtp,
          notifiedWorkerIds: freshIds,
          attempt: 2,
        },
      ),
    );
    await Promise.all(
      freshIds.map((workerId) =>
        this.redisService.addPendingBooking(workerId, bookingId).catch((e) =>
          this.logger.error(
            `inline pending add ${workerId} failed: ${
              (e as Error)?.message ?? e
            }`,
          ),
        ),
      ),
    );
    await this.outboxService.enqueueDispatch(outbox.id);

    this.logger.log(
      `[Rebroadcast] ${bookingId}: widened wave queued to ${freshIds.length} new pros`,
    );
    return { stillOpen: true, notified: freshIds.length };
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
}
