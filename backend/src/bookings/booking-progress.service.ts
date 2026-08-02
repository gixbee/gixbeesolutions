import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Booking, BookingStatus } from './booking.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { WorkersService } from '../workers/workers.service';
import { WorkerStrikeType } from '../workers/worker-strike.entity';
import { BookingStatusService } from './booking-status.service';

/**
 * GPS progress checks + strike recording while a booking is ACCEPTED.
 * Kept off the BookingsService facade so progress logic can evolve independently.
 */
@Injectable()
export class BookingProgressService {
  private readonly logger = new Logger(BookingProgressService.name);

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
    private notificationsService: NotificationsService,
    private workersService: WorkersService,
    private bookingStatusService: BookingStatusService,
  ) {}

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
    if (
      !location ||
      !Number.isFinite(location.lat) ||
      !Number.isFinite(location.lng)
    ) {
      return { progressing: false, reason: 'No recent location update found.' };
    }

    if (location.timestamp) {
      const age = nowMs - new Date(location.timestamp).getTime();
      if (
        !Number.isFinite(age) ||
        age > BookingProgressService.GPS_LOCATION_MAX_AGE_MS
      ) {
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

    if (distanceKm <= BookingProgressService.PROGRESS_NEAR_JOB_KM) {
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
      if (closerBy >= BookingProgressService.PROGRESS_MIN_CLOSER_KM) {
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

    if (
      booking.gpsStrikes >= BookingProgressService.PROGRESS_STRIKE_THRESHOLD
    ) {
      booking.workerNoProgressAt = new Date();
      await this.bookingsRepository.save(booking);

      await this.bookingStatusService.cacheAndEmitBookingStatus(bookingId, {
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

  /** Haversine distance in km. */
  calculateDistance(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
  ): number {
    const R = 6371;
    const dLat = (lat2 - lat1) * (Math.PI / 180);
    const dLon = (lon2 - lon1) * (Math.PI / 180);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * (Math.PI / 180)) *
        Math.cos(lat2 * (Math.PI / 180)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
