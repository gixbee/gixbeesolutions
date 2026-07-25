import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { WorkersService } from '../workers/workers.service';
import { MessagesGateway } from '../messages/messages.gateway';
import { OutboxEvent } from './outbox-event.entity';
import {
  BookingAcceptedPayload,
  BookingBroadcastCreatedPayload,
  BookingCancelledPayload,
  OutboxEventType,
} from './outbox.types';

/**
 * Idempotent side-effect handlers for booking lifecycle outbox events.
 * Safe to run twice: Redis set/remove, FCM duplicates, and Bull jobIds are OK.
 */
@Injectable()
export class BookingLifecycleHandler {
  private readonly logger = new Logger(BookingLifecycleHandler.name);

  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
    private readonly workersService: WorkersService,
    private readonly messagesGateway: MessagesGateway,
    @InjectQueue('bookings') private readonly bookingsQueue: Queue,
  ) {}

  async handle(event: OutboxEvent): Promise<void> {
    switch (event.type) {
      case OutboxEventType.BOOKING_BROADCAST_CREATED:
        await this.onBroadcastCreated(
          event.payload as unknown as BookingBroadcastCreatedPayload,
        );
        return;
      case OutboxEventType.BOOKING_ACCEPTED:
        await this.onAccepted(
          event.payload as unknown as BookingAcceptedPayload,
        );
        return;
      case OutboxEventType.BOOKING_CANCELLED:
        await this.onCancelled(
          event.payload as unknown as BookingCancelledPayload,
        );
        return;
      case OutboxEventType.BOOKING_COMPLETED:
      case OutboxEventType.BOOKING_PAYMENT_CONFIRMED:
        // TODO: wire listeners when BookingsService emits these types.
        this.logger.debug(`No-op listener for ${event.type} (not wired yet)`);
        return;
      default:
        this.logger.warn(`Unknown outbox type ${event.type} — marking processed`);
    }
  }

  private async onBroadcastCreated(
    p: BookingBroadcastCreatedPayload,
  ): Promise<void> {
    await this.redisService.saveOtp(
      `otp:booking:${p.bookingId}:arrival`,
      p.arrivalOtp,
    );
    await this.redisService.saveOtp(
      `otp:booking:${p.bookingId}:completion`,
      p.completionOtp,
    );

    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: p.bookingId },
      {
        jobId: `requestTimeout:${p.bookingId}`,
        delay: 90 * 1000,
        removeOnComplete: true,
      },
    );

    await this.redisService.cacheBookingStatus(p.bookingId, {
      status: 'REQUESTED',
      operatorName: null,
      operatorId: null,
      customerId: p.customerId,
      arrivalOtp: p.arrivalOtp,
    });

    const notifiedIds: string[] = [];
    await Promise.all(
      (p.notifiedWorkerIds ?? []).map(async (wid) => {
        try {
          await this.redisService.addPendingBooking(wid, p.bookingId);
          notifiedIds.push(wid);
        } catch (e) {
          this.logger.error(`pending ${wid} failed: ${(e as Error)?.message}`);
        }
      }),
    );

    if (notifiedIds.length === 0) return;

    const socketPayload = {
      id: p.bookingId,
      skill: p.skill,
      serviceLocation: p.serviceLocation,
      amount: p.amount,
      customer_name: 'Customer',
    };
    for (const wid of notifiedIds) {
      try {
        this.messagesGateway.emitUserEvent(
          wid,
          'new_booking_request',
          socketPayload,
        );
      } catch (e) {
        this.logger.error(`socket ${wid} failed: ${(e as Error)?.message}`);
      }
    }

    await this.notificationsService
      .sendToUsers(notifiedIds, {
        title: 'New Job Request',
        body: `A customer needs ${p.skill} help nearby.`,
        data: {
          type: 'new_booking',
          bookingId: p.bookingId,
          skill: p.skill,
          serviceLocation: p.serviceLocation,
          amount: String(p.amount ?? 0),
        },
      })
      .catch((e) => this.logger.error(`multicast failed: ${e?.message ?? e}`));

    await this.redisService.set(
      `booking:notified:${p.bookingId}`,
      JSON.stringify(notifiedIds),
      60 * 60,
    );
  }

  private async onAccepted(p: BookingAcceptedPayload): Promise<void> {
    try {
      await this.workersService.setWorkerStatus(p.workerId, 'busy');
    } catch (e) {
      this.logger.error(`setWorkerStatus failed: ${(e as Error)?.message}`);
    }

    try {
      await this.redisService.removePendingBooking(p.workerId, p.bookingId);
    } catch (e) {
      this.logger.error(`removePendingBooking failed: ${(e as Error)?.message}`);
    }

    try {
      await this.redisService.cacheBookingStatus(p.bookingId, {
        status: 'ACCEPTED',
        operatorName: p.operatorName,
        operatorId: p.workerId,
        customerId: p.customerId,
        arrivalOtp: p.arrivalOtp,
      });
    } catch (e) {
      this.logger.error(`cacheBookingStatus failed: ${(e as Error)?.message}`);
    }

    await this.clearAllNotifiedPending(p.bookingId);

    if ((p.cancelledCustomerIds ?? []).length > 0) {
      await this.notificationsService
        .sendToUsers(p.cancelledCustomerIds, {
          title: 'Booking Cancelled',
          body: 'The worker accepted another job. Please try booking again.',
          data: { type: 'booking_cancelled' },
        })
        .catch((e) =>
          this.logger.error(`cancel multicast failed: ${e?.message ?? e}`),
        );
    }

    await Promise.all(
      (p.cancelledBookingIds ?? []).map(async (cancelledId) => {
        try {
          await this.redisService
            .removePendingBooking(p.workerId, cancelledId)
            .catch(() => undefined);
          await this.redisService.cacheBookingStatus(cancelledId, {
            status: 'CANCELLED',
            operatorName: null,
            operatorId: p.workerId,
            customerId: null,
          });
        } catch (e) {
          this.logger.error(
            `Cancelled-cache failed for ${cancelledId}: ${(e as Error)?.message}`,
          );
        }
      }),
    );

    try {
      await this.bookingsQueue.add(
        'sevenMinuteReminder',
        { bookingId: p.bookingId },
        {
          jobId: `sevenMinuteReminder:${p.bookingId}`,
          delay: 7 * 60 * 1000,
          removeOnComplete: true,
        },
      );
      await this.bookingsQueue.add(
        'tenMinuteGpsCheck',
        { bookingId: p.bookingId },
        {
          jobId: `tenMinuteGpsCheck:${p.bookingId}`,
          delay: 10 * 60 * 1000,
          removeOnComplete: true,
        },
      );
    } catch (e) {
      this.logger.error(`Queue scheduling failed: ${(e as Error)?.message}`);
      throw e;
    }

    if (p.customerId) {
      const acceptPayload = {
        id: p.bookingId,
        bookingId: p.bookingId,
        status: 'ACCEPTED',
        operatorName: p.operatorName || '',
        operatorId: p.workerId,
        arrivalOtp: p.arrivalOtp,
      };
      try {
        this.messagesGateway.emitUserEvent(
          p.customerId,
          'booking_accepted',
          acceptPayload,
        );
      } catch (e) {
        this.logger.error(`socket emit failed: ${(e as Error)?.message}`);
      }
      await this.notificationsService
        .sendToUser(p.customerId, {
          title: 'Request Accepted!',
          body: `${p.operatorName || 'Your worker'} is on the way.`,
          data: {
            type: 'booking_accepted',
            bookingId: p.bookingId,
            operatorName: p.operatorName || '',
            operatorId: p.workerId,
          },
        })
        .catch((e) =>
          this.logger.error(`customer FCM failed: ${e?.message ?? e}`),
        );
    }
  }

  private async onCancelled(p: BookingCancelledPayload): Promise<void> {
    if (p.operatorId) {
      await this.redisService
        .removePendingBooking(p.operatorId, p.bookingId)
        .catch(() => undefined);
      if (p.source === 'customer') {
        await this.notificationsService
          .sendToUser(p.operatorId, {
            title: 'Booking cancelled',
            body: 'A customer cancelled their booking.',
            data: { type: 'booking_cancelled', bookingId: p.bookingId },
          })
          .catch(() => undefined);
      }
    }

    const notified = await this.getNotifiedWorkerIds(p.bookingId);
    await this.clearAllNotifiedPending(p.bookingId);

    const extras = (p.notifyWorkerIds ?? []).filter(
      (wid) => wid !== p.operatorId,
    );
    const others = [
      ...new Set([
        ...notified.filter((wid) => wid !== p.operatorId),
        ...extras,
      ]),
    ];

    if (p.source === 'customer' && others.length > 0) {
      await this.notificationsService
        .sendToUsers(others, {
          title: 'Booking cancelled',
          body: 'A customer cancelled their request.',
          data: { type: 'booking_cancelled', bookingId: p.bookingId },
        })
        .catch(() => undefined);
    }

    if (p.source === 'timeout' && p.customerId) {
      await this.notificationsService
        .sendToUser(p.customerId, {
          title: 'No Workers Available',
          body: 'No worker accepted your request within the time limit. Please try again.',
          data: { type: 'booking_cancelled', bookingId: p.bookingId },
        })
        .catch(() => undefined);
    }

    await this.redisService
      .cacheBookingStatus(p.bookingId, {
        status: 'CANCELLED',
        operatorName: p.operatorName,
        operatorId: p.operatorId,
        customerId: p.customerId,
        arrivalOtp: null,
      })
      .catch(() => undefined);
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

  private async clearAllNotifiedPending(bookingId: string): Promise<void> {
    const notified = await this.getNotifiedWorkerIds(bookingId);
    if (notified.length === 0) return;
    await Promise.all(
      notified.map((wid) =>
        this.redisService.removePendingBooking(wid, bookingId).catch(() => undefined),
      ),
    );
    await this.redisService.del(`booking:notified:${bookingId}`).catch(() => undefined);
  }
}
