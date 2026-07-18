import {
  Injectable,
  BadRequestException,
  ConflictException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, EntityManager } from 'typeorm';
import { RentalItem } from './rental-item.entity';
import { RentalReservation, RentalStatus } from './rental-reservation.entity';
import { User } from '../users/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { stripPrivateFields } from '../common/sanitize';

@Injectable()
export class RentalsService {
  // AUDIT FIX: the public catalog hit Postgres on every request. 60s cache,
  // invalidated on any item write (create/edit/availability toggle).
  private static readonly CATALOG_CACHE_KEY = 'rentals:catalog';

  constructor(
    @InjectRepository(RentalItem)
    private readonly rentalItemRepo: Repository<RentalItem>,
    @InjectRepository(RentalReservation)
    private readonly reservationRepo: Repository<RentalReservation>,
    private readonly notificationsService: NotificationsService,
    private readonly redisService: RedisService,
    private readonly dataSource: DataSource,
  ) {}

  private async invalidateCatalogCache(): Promise<void> {
    await this.redisService
      .del(RentalsService.CATALOG_CACHE_KEY)
      .catch(() => {});
  }

  // ── Items ──────────────────────────────────────────────────────────────────

  /** Owner lists an item. Identity comes from the JWT, never the body. */
  async createItem(ownerId: string, data: Partial<RentalItem>): Promise<RentalItem> {
    const item = this.rentalItemRepo.create({
      ...data,
      owner: { id: ownerId } as User,
    });
    const saved = await this.rentalItemRepo.save(item);
    await this.invalidateCatalogCache();
    return saved;
  }

  /** Owner edits their own item (also powers the availability toggle). */
  async updateItem(
    ownerId: string,
    itemId: string,
    data: Partial<RentalItem>,
  ): Promise<RentalItem> {
    const item = await this.rentalItemRepo.findOne({
      where: { id: itemId },
      relations: ['owner'],
    });
    if (!item) throw new NotFoundException('Rental item not found');
    if (item.owner?.id !== ownerId) {
      throw new ForbiddenException('You can only edit your own items');
    }
    Object.assign(item, data);
    const saved = await this.rentalItemRepo.save(item);
    await this.invalidateCatalogCache(); // price/photo/availability changed
    return saved;
  }

  /** Public catalog: available items only (Redis-cached, 60s, capped). */
  async getItems(): Promise<RentalItem[]> {
    const cached = await this.redisService.get(
      RentalsService.CATALOG_CACHE_KEY,
    );
    if (cached) return JSON.parse(cached) as RentalItem[];

    // AUDIT FIX: hard take — catalog must not load every row into Redis/memory.
    const rows = await this.rentalItemRepo.find({
      where: { isAvailable: true },
      relations: ['owner'],
      order: { createdAt: 'DESC' },
      take: 100,
    });

    // Cached payloads are plain objects the ClassSerializerInterceptor can't
    // sanitize — strip the owner's private fields before caching.
    const items = stripPrivateFields(rows);
    await this.redisService
      .set(RentalsService.CATALOG_CACHE_KEY, JSON.stringify(items), 60)
      .catch(() => {});
    return items;
  }

  /** Owner's own items (any availability). */
  async getMyItems(
    ownerId: string,
    page = 1,
    limit = 50,
  ): Promise<RentalItem[]> {
    return this.rentalItemRepo.find({
      where: { owner: { id: ownerId } },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  /** Item detail + its CONFIRMED/ACTIVE windows so pickers can grey them. */
  async getItemDetail(itemId: string): Promise<any> {
    const item = await this.rentalItemRepo.findOne({
      where: { id: itemId },
      relations: ['owner'],
    });
    if (!item) throw new NotFoundException('Rental item not found');
    const booked = await this.reservationRepo.find({
      where: [
        { item: { id: itemId }, status: RentalStatus.CONFIRMED },
        { item: { id: itemId }, status: RentalStatus.ACTIVE },
      ],
      order: { startTime: 'ASC' },
      take: 200,
    });
    return {
      ...item,
      bookedRanges: booked.map((r) => ({
        start: r.startTime,
        end: r.endTime,
      })),
    };
  }

  // ── Reservations ───────────────────────────────────────────────────────────

  /**
   * Customer requests a reservation. Enforces min-hours + overlap checks;
   * price = ceil(days) × dailyRate when a daily rate exists and the span is
   * ≥ 24h, else hours × hourlyRate. Owner gets a push to confirm.
   *
   * AUDIT FIX (TOCTOU): overlap check + insert run inside a transaction that
   * takes a pessimistic write lock on the rental item row, serializing all
   * reserve/confirm traffic for that item so two concurrent callers cannot
   * both pass checkOverlap.
   */
  async requestReservation(
    renterId: string,
    itemId: string,
    startTime: Date,
    endTime: Date,
  ): Promise<RentalReservation> {
    const start = new Date(startTime);
    const end = new Date(endTime);
    if (start >= end) {
      throw new BadRequestException('End time must be after start time.');
    }
    if (start.getTime() < Date.now() - 60 * 1000) {
      throw new BadRequestException('Start time cannot be in the past.');
    }

    const saved = await this.dataSource.transaction(async (manager) => {
      const item = await this.lockItem(manager, itemId);
      if (!item.isAvailable) {
        throw new BadRequestException(
          'This item is currently listed as unavailable.',
        );
      }
      if (item.owner?.id === renterId) {
        throw new BadRequestException('You cannot reserve your own item.');
      }

      const durationMs = end.getTime() - start.getTime();
      const durationHours = durationMs / (1000 * 60 * 60);
      if (durationHours < item.minHoursToRent) {
        throw new BadRequestException(
          `This item requires a minimum rental period of ${item.minHoursToRent} hours.`,
        );
      }

      if (await this.checkOverlap(manager, itemId, start, end)) {
        throw new ConflictException(
          'This rental item is already booked for the selected dates/times.',
        );
      }

      let totalPrice: number;
      if (item.dailyRate && durationHours >= 24) {
        totalPrice = Math.ceil(durationHours / 24) * Number(item.dailyRate);
      } else {
        totalPrice = Math.ceil(durationHours) * Number(item.hourlyRate);
      }

      const reservationRepo = manager.getRepository(RentalReservation);
      const reservation = reservationRepo.create({
        item: { id: itemId } as RentalItem,
        renter: { id: renterId } as User,
        startTime: start,
        endTime: end,
        totalPrice,
        status: RentalStatus.PENDING,
      });
      return reservationRepo.save(reservation);
    });

    // Notify outside the lock so FCM latency doesn't hold the row.
    const item = await this.rentalItemRepo.findOne({
      where: { id: itemId },
      relations: ['owner'],
    });
    if (item?.owner?.id) {
      await this.notificationsService
        .sendToUser(item.owner.id, {
          title: 'New rental request',
          body: `Someone wants to rent "${item.name}" — confirm or reject in the app.`,
          data: { type: 'rental_request', reservationId: saved.id },
        })
        .catch(() => {});
    }
    return saved;
  }

  /** Customer's reservations (with item + owner for display). */
  async myReservations(
    renterId: string,
    page = 1,
    limit = 50,
  ): Promise<RentalReservation[]> {
    return this.reservationRepo.find({
      where: { renter: { id: renterId } },
      relations: ['item', 'item.owner'],
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }

  /** Owner's incoming reservations across all their items. */
  async ownerReservations(
    ownerId: string,
    page = 1,
    limit = 50,
  ): Promise<RentalReservation[]> {
    return this.reservationRepo
      .createQueryBuilder('r')
      .leftJoinAndSelect('r.item', 'item')
      .leftJoinAndSelect('item.owner', 'owner')
      .leftJoinAndSelect('r.renter', 'renter')
      .where('owner.id = :ownerId', { ownerId })
      .orderBy('r.createdAt', 'DESC')
      .skip((page - 1) * limit)
      .take(limit)
      .getMany();
  }

  /** Shared loader with owner check for the decision endpoints. */
  private async loadForOwner(
    reservationId: string,
    ownerId: string,
    manager?: EntityManager,
  ): Promise<RentalReservation> {
    const repo = manager
      ? manager.getRepository(RentalReservation)
      : this.reservationRepo;
    const reservation = await repo.findOne({
      where: { id: reservationId },
      relations: ['item', 'item.owner', 'renter'],
    });
    if (!reservation) throw new NotFoundException('Reservation not found');
    if (reservation.item?.owner?.id !== ownerId) {
      throw new ForbiddenException(
        'Only the item owner can act on this reservation',
      );
    }
    return reservation;
  }

  /**
   * Owner confirms — re-checks overlap under the same item lock used by
   * requestReservation so concurrent confirms cannot both succeed.
   */
  async confirmReservation(
    reservationId: string,
    ownerId: string,
  ): Promise<RentalReservation> {
    const saved = await this.dataSource.transaction(async (manager) => {
      const reservation = await this.loadForOwner(
        reservationId,
        ownerId,
        manager,
      );
      if (reservation.status !== RentalStatus.PENDING) {
        throw new BadRequestException(
          `Cannot confirm a reservation with status ${reservation.status}`,
        );
      }

      await this.lockItem(manager, reservation.item.id);

      // Re-read status after acquiring the item lock — another confirm may
      // have won the race while we waited.
      const fresh = await manager.getRepository(RentalReservation).findOne({
        where: { id: reservationId },
      });
      if (!fresh || fresh.status !== RentalStatus.PENDING) {
        throw new BadRequestException(
          `Cannot confirm a reservation with status ${fresh?.status ?? 'UNKNOWN'}`,
        );
      }

      if (
        await this.checkOverlap(
          manager,
          reservation.item.id,
          reservation.startTime,
          reservation.endTime,
        )
      ) {
        throw new ConflictException(
          'The requested time slot has been booked by someone else in the meantime.',
        );
      }

      reservation.status = RentalStatus.CONFIRMED;
      return manager.getRepository(RentalReservation).save(reservation);
    });

    await this.notifyRenter(
      saved,
      'Rental confirmed',
      `Your reservation for "${saved.item?.name ?? 'item'}" is confirmed.`,
    );
    return saved;
  }

  async rejectReservation(
    reservationId: string,
    ownerId: string,
  ): Promise<RentalReservation> {
    const reservation = await this.loadForOwner(reservationId, ownerId);
    if (reservation.status !== RentalStatus.PENDING) {
      throw new BadRequestException(
        `Cannot reject a reservation with status ${reservation.status}`,
      );
    }
    reservation.status = RentalStatus.REJECTED;
    const saved = await this.reservationRepo.save(reservation);
    await this.notifyRenter(saved, 'Rental request declined',
        `The owner declined your request for "${reservation.item.name}".`);
    return saved;
  }

  /** Owner marks handover (CONFIRMED → ACTIVE) at pickup. */
  async startReservation(
    reservationId: string,
    ownerId: string,
  ): Promise<RentalReservation> {
    const reservation = await this.loadForOwner(reservationId, ownerId);
    if (reservation.status !== RentalStatus.CONFIRMED) {
      throw new BadRequestException('Only confirmed reservations can start');
    }
    reservation.status = RentalStatus.ACTIVE;
    return this.reservationRepo.save(reservation);
  }

  /** Owner marks the item returned (ACTIVE → COMPLETED). */
  async completeReservation(
    reservationId: string,
    ownerId: string,
  ): Promise<RentalReservation> {
    const reservation = await this.loadForOwner(reservationId, ownerId);
    if (reservation.status !== RentalStatus.ACTIVE) {
      throw new BadRequestException('Only active rentals can be completed');
    }
    reservation.status = RentalStatus.COMPLETED;
    const saved = await this.reservationRepo.save(reservation);
    await this.notifyRenter(saved, 'Rental completed',
        `"${reservation.item.name}" was returned — thanks for renting on Gixbee!`);
    return saved;
  }

  /** Customer cancels their own PENDING/CONFIRMED reservation. */
  async cancelReservation(
    reservationId: string,
    renterId: string,
  ): Promise<RentalReservation> {
    const reservation = await this.reservationRepo.findOne({
      where: { id: reservationId },
      relations: ['item', 'item.owner', 'renter'],
    });
    if (!reservation) throw new NotFoundException('Reservation not found');
    if (reservation.renter?.id !== renterId) {
      throw new ForbiddenException('You can only cancel your own reservations');
    }
    if (reservation.status !== RentalStatus.PENDING &&
        reservation.status !== RentalStatus.CONFIRMED) {
      throw new BadRequestException(
        `Cannot cancel a reservation with status ${reservation.status}`,
      );
    }
    reservation.status = RentalStatus.CANCELLED;
    const saved = await this.reservationRepo.save(reservation);
    if (reservation.item?.owner?.id) {
      await this.notificationsService
        .sendToUser(reservation.item.owner.id, {
          title: 'Rental cancelled',
          body: `The reservation for "${reservation.item.name}" was cancelled by the renter.`,
          data: { type: 'rental_cancelled', reservationId },
        })
        .catch(() => {});
    }
    return saved;
  }

  private async notifyRenter(
    reservation: RentalReservation,
    title: string,
    body: string,
  ): Promise<void> {
    if (reservation.renter?.id) {
      await this.notificationsService
        .sendToUser(reservation.renter.id, {
          title,
          body,
          data: { type: 'rental_update', reservationId: reservation.id },
        })
        .catch(() => {});
    }
  }

  /**
   * Serialize reserve/confirm for one catalog item. Lock the item row only
   * (no joins — Postgres rejects FOR UPDATE with LEFT JOIN).
   */
  private async lockItem(
    manager: EntityManager,
    itemId: string,
  ): Promise<RentalItem> {
    const locked = await manager
      .getRepository(RentalItem)
      .createQueryBuilder('item')
      .setLock('pessimistic_write')
      .where('item.id = :itemId', { itemId })
      .getOne();
    if (!locked) throw new NotFoundException('Rental item not found');

    // Re-load with owner relation for self-book / notify checks (row already locked).
    const withOwner = await manager.getRepository(RentalItem).findOne({
      where: { id: itemId },
      relations: ['owner'],
    });
    return withOwner ?? locked;
  }

  /** Overlap vs CONFIRMED/ACTIVE windows (calendar block logic). */
  private async checkOverlap(
    manager: EntityManager,
    itemId: string,
    start: Date,
    end: Date,
  ): Promise<boolean> {
    const conflictingBooking = await manager
      .getRepository(RentalReservation)
      .createQueryBuilder('reservation')
      .innerJoin('reservation.item', 'item')
      .where('item.id = :itemId', { itemId })
      .andWhere('reservation.status IN (:...statuses)', {
        statuses: [RentalStatus.CONFIRMED, RentalStatus.ACTIVE],
      })
      .andWhere('reservation.endTime > :start', { start })
      .andWhere('reservation.startTime < :end', { end })
      .getOne();
    return !!conflictingBooking;
  }
}
