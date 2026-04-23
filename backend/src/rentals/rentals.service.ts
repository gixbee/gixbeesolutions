import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { RentalItem } from './rental-item.entity';
import { RentalReservation, RentalStatus } from './rental-reservation.entity';
import { User } from '../users/user.entity';

@Injectable()
export class RentalsService {
  constructor(
    @InjectRepository(RentalItem)
    private readonly rentalItemRepo: Repository<RentalItem>,
    @InjectRepository(RentalReservation)
    private readonly reservationRepo: Repository<RentalReservation>,
  ) {}

  /**
   * Create a new item to be rented out
   */
  async createItem(ownerId: string, data: Partial<RentalItem>): Promise<RentalItem> {
    const item = this.rentalItemRepo.create({
      ...data,
      owner: { id: ownerId } as User,
    });
    return this.rentalItemRepo.save(item);
  }

  /**
   * List available items
   */
  async getItems(): Promise<RentalItem[]> {
    return this.rentalItemRepo.find({
      where: { isAvailable: true },
      relations: ['owner'],
    });
  }

  /**
   * Attempt to create a reservation.
   * Enforces min-hour billing and checks for overlaps conditionally.
   */
  async requestReservation(renterId: string, itemId: string, startTime: Date, endTime: Date): Promise<RentalReservation> {
    const item = await this.rentalItemRepo.findOne({ where: { id: itemId } });
    if (!item) {
      throw new NotFoundException('Rental item not found');
    }

    if (!item.isAvailable) {
      throw new BadRequestException('This item is currently listed as unavailable.');
    }

    const start = new Date(startTime);
    const end = new Date(endTime);

    if (start >= end) {
      throw new BadRequestException('End time must be after start time.');
    }

    // Min-hour billing constraint
    const durationMs = end.getTime() - start.getTime();
    const durationHours = durationMs / (1000 * 60 * 60);

    if (durationHours < item.minHoursToRent) {
      throw new BadRequestException(`This item requires a minimum rental period of ${item.minHoursToRent} hours.`);
    }

    // Check for hard overlaps with CONFIRMED or ACTIVE reservations
    const hasOverlap = await this.checkOverlap(itemId, start, end);
    if (hasOverlap) {
      throw new ConflictException('This rental item is already booked for the selected dates/times.');
    }

    // Calculate price
    const totalPrice = durationHours * Number(item.hourlyRate);

    const reservation = this.reservationRepo.create({
      item: { id: itemId } as RentalItem,
      renter: { id: renterId } as User,
      startTime: start,
      endTime: end,
      totalPrice,
      status: RentalStatus.PENDING,
    });

    return this.reservationRepo.save(reservation);
  }

  /**
   * Confirms a reservation, officially "blocking" the calendar day/timeslot.
   * Validates one more time to ensure no race conditions occurred.
   */
  async confirmReservation(reservationId: string): Promise<RentalReservation> {
    const reservation = await this.reservationRepo.findOne({ 
      where: { id: reservationId },
      relations: ['item'] 
    });

    if (!reservation) {
      throw new NotFoundException('Reservation not found');
    }

    if (reservation.status !== RentalStatus.PENDING) {
      throw new BadRequestException(`Cannot confirm a reservation with status ${reservation.status}`);
    }

    // Final calendar day-block check
    const hasOverlap = await this.checkOverlap(reservation.item.id, reservation.startTime, reservation.endTime);
    if (hasOverlap) {
      throw new ConflictException('The requested time slot has been booked by someone else in the meantime.');
    }

    reservation.status = RentalStatus.CONFIRMED;
    return this.reservationRepo.save(reservation);
  }

  /**
   * Helper: Check if a given start and end time overlaps with any confirmed bookings for an item.
   * Calendar day-block logic.
   */
  private async checkOverlap(itemId: string, start: Date, end: Date): Promise<boolean> {
    // Overlap condition: An existing reservation ends AFTER the requested start,
    // AND starts BEFORE the requested end.
    const conflictingBooking = await this.reservationRepo.createQueryBuilder('reservation')
      .where('reservation.item.id = :itemId', { itemId })
      .andWhere('reservation.status IN (:...statuses)', { statuses: [RentalStatus.CONFIRMED, RentalStatus.ACTIVE] })
      .andWhere('reservation.endTime > :start', { start })
      .andWhere('reservation.startTime < :end', { end })
      .getOne();

    return !!conflictingBooking;
  }
}
