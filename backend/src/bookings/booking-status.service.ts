import {
  Injectable,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Booking, BookingStatus, BookingType } from './booking.entity';
import { RedisService } from '../redis/redis.service';
import { MessagesGateway } from '../messages/messages.gateway';
import { MasterEntriesService } from '../master-entries/master-entries.service';

@Injectable()
export class BookingStatusService {
  private readonly logger = new Logger(BookingStatusService.name);

  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    private redisService: RedisService,
    private messagesGateway: MessagesGateway,
    private masterEntriesService: MasterEntriesService,
  ) {}

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
  /**
   * Role-aware dial target for Call buttons. Customer gets the assigned
   * pro's phone; worker gets on-site contact phone when set, else customer.
   */
  private resolveCounterpartPhone(
    isCustomer: boolean,
    phones: {
      customerPhone?: string | null;
      operatorPhone?: string | null;
      onSiteContactPhone?: string | null;
    },
  ): string | null {
    const clean = (v?: string | null) => {
      const s = (v ?? '').trim();
      return s.length > 0 ? s : null;
    };
    if (isCustomer) return clean(phones.operatorPhone);
    return clean(phones.onSiteContactPhone) ?? clean(phones.customerPhone);
  }

  private extractBookingPhones(booking: {
    customer?: { phoneNumber?: string | null } | null;
    operator?: { phoneNumber?: string | null } | null;
    onSiteContact?: { phone?: string | null } | null;
  }): {
    customerPhone: string | null;
    operatorPhone: string | null;
    onSiteContactPhone: string | null;
  } {
    const clean = (v?: string | null) => {
      const s = (v ?? '').trim();
      return s.length > 0 ? s : null;
    };
    return {
      customerPhone: clean(booking.customer?.phoneNumber),
      operatorPhone: clean(booking.operator?.phoneNumber),
      onSiteContactPhone: clean(booking.onSiteContact?.phone),
    };
  }

  private async billingExtras(booking: Booking): Promise<{
    skill: string | null;
    type: string | null;
    hourlyRate: number | null;
    acceptDistanceKm: number | null;
    petrolRatePerKm: number | null;
    estimatedPetrolAmount: number | null;
  }> {
    const hourlyRate = Number(booking.amount);
    const dist = Number(booking.acceptDistanceKm);
    const isInstant = booking.type === BookingType.INSTANT;
    const acceptDistanceKm =
      Number.isFinite(dist) && dist > 0 ? Math.round(dist * 100) / 100 : null;
    let petrolRatePerKm: number | null = null;
    let estimatedPetrolAmount: number | null = null;
    if (isInstant && acceptDistanceKm != null) {
      petrolRatePerKm = await this.masterEntriesService.getConfigNumber(
        'instant_petrol_per_km',
        10,
      );
      estimatedPetrolAmount = Math.round(acceptDistanceKm * petrolRatePerKm);
    }
    return {
      skill: booking.skill ?? null,
      type: booking.type ?? null,
      hourlyRate: Number.isFinite(hourlyRate) ? hourlyRate : null,
      acceptDistanceKm,
      petrolRatePerKm,
      estimatedPetrolAmount,
    };
  }

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
    /** Phone to dial for the other party on this booking. */
    counterpartPhone: string | null;
    skill?: string | null;
    type?: string | null;
    hourlyRate?: number | null;
    acceptDistanceKm?: number | null;
    petrolRatePerKm?: number | null;
    estimatedPetrolAmount?: number | null;
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
      let status = String(cached.status || '').toUpperCase();

      // Stale open-status cache: accept commits to Postgres before the outbox
      // refreshes Redis. If we still serve REQUESTED, the customer stays on
      // "Finding your pro" and can cancel an already-accepted job.
      const openCached = new Set([
        'REQUESTED',
        'PENDING',
        'CUSTOM_REQUESTED',
      ]);
      if (openCached.has(status)) {
        const fresh = await this.getBookingById(bookingId);
        if (fresh) {
          const dbStatus = String(fresh.status || '').toUpperCase();
          if (dbStatus && dbStatus !== status) {
            const phones = this.extractBookingPhones(fresh);
            const billing = await this.billingExtras(fresh);
            const payload = {
              status: fresh.status,
              operatorName: fresh.operator?.name ?? null,
              operatorId: fresh.operator?.id ?? null,
              customerId: fresh.customer?.id ?? null,
              arrivalOtp: fresh.arrivalOtp,
              cancelRequested: !!fresh.cancelRequestedAt,
              workerNoProgress: !!fresh.workerNoProgressAt,
              isPaid: !!fresh.isPaid,
              workerPaidConfirmed: !!fresh.workerPaidConfirmed,
              customerPaidConfirmed: !!fresh.customerPaidConfirmed,
              ...phones,
              ...billing,
            };
            await this.redisService
              .cacheBookingStatus(bookingId, payload)
              .catch(() => {});
            const loc = await attachOperatorLocation(
              payload.operatorId,
              dbStatus,
            );
            return {
              status: dbStatus,
              operatorName: payload.operatorName,
              operatorId: payload.operatorId,
              arrivalOtp:
                isCustomer && dbStatus === 'ACCEPTED'
                  ? (fresh.arrivalOtp ?? null)
                  : null,
              cancelRequested: payload.cancelRequested,
              workerNoProgress: payload.workerNoProgress,
              isPaid: payload.isPaid,
              workerPaidConfirmed: payload.workerPaidConfirmed,
              customerPaidConfirmed: payload.customerPaidConfirmed,
              operatorLat: loc.operatorLat,
              operatorLng: loc.operatorLng,
              counterpartPhone: this.resolveCounterpartPhone(
                isCustomer,
                phones,
              ),
              ...billing,
            };
          }
        }
      }

      const loc = await attachOperatorLocation(cached.operatorId, status);

      let phones = {
        customerPhone: (cached.customerPhone as string | null) ?? null,
        operatorPhone: (cached.operatorPhone as string | null) ?? null,
        onSiteContactPhone:
          (cached.onSiteContactPhone as string | null) ?? null,
      };
      let counterpartPhone = this.resolveCounterpartPhone(isCustomer, phones);

      // Older cache writes omit phones — enrich once from DB and merge back.
      if (!counterpartPhone) {
        const booking = await this.getBookingById(bookingId);
        if (booking) {
          phones = this.extractBookingPhones(booking);
          counterpartPhone = this.resolveCounterpartPhone(isCustomer, phones);
          if (counterpartPhone) {
            await this.redisService
              .cacheBookingStatus(bookingId, { ...cached, ...phones })
              .catch(() => {});
          }
        }
      }

      const billing =
        cached.hourlyRate != null || cached.acceptDistanceKm != null
          ? {
              skill: cached.skill ?? null,
              type: cached.type ?? null,
              hourlyRate: cached.hourlyRate ?? null,
              acceptDistanceKm: cached.acceptDistanceKm ?? null,
              petrolRatePerKm: cached.petrolRatePerKm ?? null,
              estimatedPetrolAmount: cached.estimatedPetrolAmount ?? null,
            }
          : await this.getBookingById(bookingId).then((b) =>
              b ? this.billingExtras(b) : Promise.resolve({
                skill: null,
                type: null,
                hourlyRate: null,
                acceptDistanceKm: null,
                petrolRatePerKm: null,
                estimatedPetrolAmount: null,
              }),
            );

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
        counterpartPhone,
        ...billing,
      };
    }

    const booking = await this.getBookingById(bookingId);
    if (!booking) throw new NotFoundException('Booking not found');
    const isCustomer = booking.customer?.id === userId;
    const isOperator = booking.operator?.id === userId;
    if (!isCustomer && !isOperator) {
      throw new NotFoundException('Booking not found');
    }

    const phones = this.extractBookingPhones(booking);
    const billing = await this.billingExtras(booking);
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
      ...phones,
      ...billing,
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
      counterpartPhone: this.resolveCounterpartPhone(isCustomer, phones),
      ...billing,
    };
  }
}
