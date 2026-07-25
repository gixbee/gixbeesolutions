import { Process, Processor } from '@nestjs/bull';
import { InjectQueue } from '@nestjs/bull';
import { Logger } from '@nestjs/common';
import type { Job, Queue } from 'bull';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';
import { RedisService } from '../redis/redis.service';
import { NotificationsService } from '../notifications/notifications.service';
import { WorkersService } from '../workers/workers.service';
import { SystemLogsService } from '../system-logs/system-logs.service';
import {
  SystemLogLevel,
  SystemLogType,
} from '../system-logs/system-log.entity';

@Processor('bookings')
export class BookingsProcessor {
  private readonly logger = new Logger(BookingsProcessor.name);

  constructor(
    private readonly bookingsService: BookingsService,
    private readonly redisService: RedisService,
    private readonly notificationsService: NotificationsService,
    private readonly workersService: WorkersService,
    private readonly systemLogs: SystemLogsService,
    @InjectQueue('bookings') private readonly bookingsQueue: Queue,
  ) {}

  /** Persist unexpected job crashes so they appear in admin System Logs. */
  private recordJobError(jobName: string, job: Job, err: unknown): void {
    const msg = err instanceof Error ? err.message : String(err);
    const stack = err instanceof Error ? err.stack ?? null : null;
    const bookingId = (job.data as { bookingId?: string })?.bookingId;
    this.systemLogs.record({
      level: SystemLogLevel.ERROR,
      type: SystemLogType.SYSTEM,
      path: `bull://bookings/${jobName}`,
      message: `Bookings job ${jobName} failed${bookingId ? ` (${bookingId.slice(0, 8)}…)` : ''}: ${msg}`,
      detail: [
        `jobId=${job.id}`,
        bookingId ? `bookingId=${bookingId}` : null,
        msg,
        stack,
      ]
        .filter(Boolean)
        .join('\n'),
    });
  }

  @Process('sevenMinuteReminder')
  async handleSevenMinuteReminder(job: Job) {
    try {
      const { bookingId } = job.data;
      this.logger.log(`Starting 7-minute reminder for booking: ${bookingId}`);

      const booking = await this.bookingsService.getBookingById(bookingId);
      if (!booking) return;

      if (booking.status !== BookingStatus.ACCEPTED) {
        return { status: 'Skipped - Not ACCEPTED' };
      }

      if (booking.operator?.id) {
        await this.notificationsService.sendToUser(booking.operator.id, {
          title: 'Reminder: Customer is waiting',
          body: 'Please confirm you are on your way. Auto-check in 3 minutes.',
        });
      }

      return { status: 'Reminder Sent' };
    } catch (err) {
      this.recordJobError('sevenMinuteReminder', job, err);
      throw err;
    }
  }

  @Process('tenMinuteGpsCheck')
  async handleTenMinuteGpsCheck(job: Job) {
    try {
      const { bookingId } = job.data;
      this.logger.log(`Starting GPS movement check for booking: ${bookingId}`);

      const booking = await this.bookingsService.getBookingById(bookingId);
      if (!booking) return;

      // Only run movement check if the booking is still pending arrival (ACCEPTED)
      if (booking.status !== BookingStatus.ACCEPTED) {
        this.logger.debug(
          `Booking ${bookingId} has status ${booking.status}. Stopping monitoring.`,
        );
        return { status: 'Monitoring Stopped - Job Active or Cancelled' };
      }

      const workerId = booking.operator?.id;
      if (!workerId) return;

      const locationCache = await this.redisService.getWorkerLocation(workerId);

      let isViolating = false;
      let reason = '';

      if (!locationCache) {
        isViolating = true;
        reason = 'No recent location update found.';
      } else {
        const distance = this.bookingsService.calculateDistance(
          locationCache.lat,
          locationCache.lng,
          Number(booking.serviceLat),
          Number(booking.serviceLng),
        );

        // Rule: Worker must be within 5km 10 minutes after acceptance
        if (distance > 5) {
          isViolating = true;
          reason = `Worker is too far (${distance.toFixed(2)} km) from destination.`;
        }
      }

      if (isViolating) {
        this.logger.warn(`⚠️ GPS Violation for Booking ${bookingId}: ${reason}`);

        const result = await this.bookingsService.addGpsStrike(bookingId);

        if (result && !result.cancelled) {
          // Reschedule another check in 3 minutes
          await this.bookingsQueue.add(
            'tenMinuteGpsCheck',
            { bookingId },
            { delay: 3 * 60 * 1000 },
          );
          return {
            status: `Strike ${result.strikes} issued. Rescheduled check in 3m.`,
          };
        }

        return { status: 'Booking forfeited due to 3 strikes.' };
      }

      this.logger.log(`Worker ${workerId} movement verified.`);
      return { status: 'GPS Verified' };
    } catch (err) {
      this.recordJobError('tenMinuteGpsCheck', job, err);
      throw err;
    }
  }

  @Process('requestTimeout')
  async handleRequestTimeout(job: Job) {
    try {
      const { bookingId } = job.data;
      this.logger.log(
        `Checking 90-second request timeout for booking: ${bookingId}`,
      );

      const booking = await this.bookingsService.getBookingById(bookingId);
      if (!booking) return;

      // Only cancel if the booking is still REQUESTED (no worker accepted yet)
      if (booking.status !== BookingStatus.REQUESTED) {
        this.logger.debug(
          `Booking ${bookingId} is ${booking.status}. Timeout skipped.`,
        );
        return { status: 'Skipped - Already accepted' };
      }

      // Auto-cancel the request (outbox BOOKING_CANCELLED + timeout FCM via listener)
      await this.bookingsService.updateStatus(
        bookingId,
        BookingStatus.CANCELLED,
      );

      this.logger.warn(
        `Booking ${bookingId} auto-cancelled — no worker accepted within 90 seconds.`,
      );
      return { status: 'Cancelled - Timeout' };
    } catch (err) {
      this.recordJobError('requestTimeout', job, err);
      throw err;
    }
  }
}
