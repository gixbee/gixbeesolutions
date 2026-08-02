import {
  Injectable,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Booking, BookingStatus } from './booking.entity';
import { RedisService } from '../redis/redis.service';
import { MessagesGateway } from '../messages/messages.gateway';

@Injectable()
export class BookingStatusService {
  private readonly logger = new Logger(BookingStatusService.name);

  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    private redisService: RedisService,
    private messagesGateway: MessagesGateway,
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
    };
  }
}
