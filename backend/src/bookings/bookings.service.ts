import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { InjectQueue } from '@nestjs/bull';
import type { Queue } from 'bull';
import { Booking, BookingStatus } from './booking.entity';
import { WalletsService } from '../wallets/wallets.service';
import { WorkerProfile } from '../workers/worker-profile.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { RedisService } from '../redis/redis.service';
import { WorkersService } from '../workers/workers.service';

@Injectable()
export class BookingsService {
  constructor(
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    @InjectRepository(WorkerProfile)
    private workerProfileRepo: Repository<WorkerProfile>,
    @InjectQueue('bookings') private bookingsQueue: Queue,
    private walletsService: WalletsService,
    private notificationsService: NotificationsService,
    private redisService: RedisService,
    private workersService: WorkersService,
  ) {}

  /** Generate a random 4-digit OTP */
  private generateOtp(): string {
    return Math.floor(1000 + Math.random() * 9000).toString();
  }

  async createBooking(bookingData: Partial<Booking>): Promise<Booking> {
    // Self-booking check
    const customerId = bookingData.customer?.id || bookingData.customer;
    const operatorId = bookingData.operator?.id || bookingData.operator;
    
    if (customerId && operatorId && customerId === operatorId) {
      throw new BadRequestException('You cannot book yourself.');
    }

    // Overlap/Double-booking check
    if (bookingData.operator?.id) {
      const activeBooking = await this.bookingsRepository.findOne({
        where: [
          { operator: { id: bookingData.operator.id }, status: BookingStatus.ACTIVE },
          { operator: { id: bookingData.operator.id }, status: BookingStatus.ACCEPTED },
          { operator: { id: bookingData.operator.id }, status: BookingStatus.CONFIRMED },
        ],
      });

      if (activeBooking) {
        throw new BadRequestException('This worker is currently on another job or has a pending task.');
      }
    }

    // Generate both OTPs at booking creation time
    const arrivalOtp = this.generateOtp();
    const completionOtp = this.generateOtp();

    const booking = this.bookingsRepository.create({
      ...bookingData,
      status: BookingStatus.REQUESTED,
      arrivalOtp,
      completionOtp,
    });
    const savedBooking = await this.bookingsRepository.save(booking);

    // Save OTPs to Redis with a 24-hour TTL (usually jobs are same-day)
    // Key format: otp:booking:{id}:arrival and otp:booking:{id}:completion
    await this.redisService.saveOtp(`otp:booking:${savedBooking.id}:arrival`, arrivalOtp);
    await this.redisService.saveOtp(`otp:booking:${savedBooking.id}:completion`, completionOtp);

    // Schedule 90-second request timeout
    await this.bookingsQueue.add(
      'requestTimeout',
      { bookingId: savedBooking.id },
      { delay: 90 * 1000 },
    );

    // PERSISTENCE OPTIMIZATION: Add to Redis for high-frequency polling
    if (bookingData.operator?.id) {
       await this.redisService.addPendingBooking(bookingData.operator.id, savedBooking.id);
    }

    // Dispatch push notification to the assigned worker via OneSignal
    if (bookingData.operator?.id) {
      await this.notificationsService.sendToUser(bookingData.operator.id, {
        title: 'New Job Request',
        body: 'A customer has requested your services.',
        data: { type: 'new_booking', bookingId: savedBooking.id },
      });
    }

    return savedBooking;
  }

  // ─── STEP 4: WORKER ACCEPTANCE ────────────────────────────

  async acceptBooking(bookingId: string, workerId: string): Promise<{ message: string; status: string; booking: Booking }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    // Only REQUESTED bookings can be accepted
    if (booking.status !== BookingStatus.REQUESTED) {
      throw new BadRequestException('This booking is no longer available for acceptance.');
    }

    // Validate the worker is the assigned operator
    if (booking.operator?.id !== workerId) {
      throw new BadRequestException('You are not assigned to this booking.');
    }

    // Deduct platform fee from worker wallet
    await this.walletsService.deductBookingFee(workerId);

    // Transition: REQUESTED → ACCEPTED
    booking.status = BookingStatus.ACCEPTED;
    const savedBooking = await this.bookingsRepository.save(booking);

    // REDIS SYNC: Remove from pending requests discovery
    await this.redisService.removePendingBooking(workerId, bookingId);

    // Update Redis status to 'busy'
    await this.workersService.setWorkerStatus(workerId, 'busy');

    // NOW schedule the 7-minute reminder and 10-minute GPS check
    await this.bookingsQueue.add(
      'sevenMinuteReminder',
      { bookingId: savedBooking.id },
      { delay: 7 * 60 * 1000 },
    );

    await this.bookingsQueue.add(
      'tenMinuteGpsCheck',
      { bookingId: savedBooking.id },
      { delay: 10 * 60 * 1000 },
    );

    return {
      message: 'Booking accepted. Head to the service location now.',
      status: 'ACCEPTED',
      booking: savedBooking,
    };
  }

  async updateStatus(id: string, status: BookingStatus): Promise<Booking | null> {
    const booking = await this.bookingsRepository.findOne({ 
      where: { id },
      relations: ['operator'] 
    });
    if (!booking) return null;

    booking.status = status;
    const saved = await this.bookingsRepository.save(booking);

    // Clean up Redis discovery if cancelled/rejected
    if (status === BookingStatus.CANCELLED || status === BookingStatus.REJECTED) {
      if (booking.operator?.id) {
        await this.redisService.removePendingBooking(booking.operator.id, id);
      }
    }

    return saved;
  }

  // ─── STEP 5: MONITORING & GPS STRIKES ─────────────────────

  /**
   * Calculates distance between two coordinates in kilometers using Haversine formula.
   */
  calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371; // Earth's radius in km
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

  /**
   * Adds a GPS strike to a booking. Cancels the booking if 3 strikes are reached.
   */
  async addGpsStrike(bookingId: string) {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer', 'operator'],
    });

    if (!booking) return;

    // Only add strikes if the booking is still in ACCEPTED status (arrival monitoring)
    if (booking.status !== BookingStatus.ACCEPTED) {
      return { status: 'Skipped - Not in monitoring phase' };
    }

    booking.gpsStrikes += 1;
    await this.bookingsRepository.save(booking);

    if (booking.gpsStrikes >= 3) {
      // Auto-cancel booking
      booking.status = BookingStatus.CANCELLED;
      await this.bookingsRepository.save(booking);

      // Notify customer via OneSignal
      if (booking.customer?.id) {
        await this.notificationsService.sendToUser(booking.customer.id, {
          title: 'Booking Cancelled',
          body: 'Your booking has been cancelled.',
          data: { type: 'booking_cancelled' },
        });
      }

      // Notify worker
      if (booking.operator?.id) {
        await this.notificationsService.sendToUser(booking.operator.id, {
          title: 'Booking Forfeited',
          body: 'You received 3 GPS strikes for not moving towards the site. The job has been forfeited.',
        });
      }

      // Mark worker as available in Redis again
      if (booking.operator?.id) {
        await this.workersService.setWorkerStatus(booking.operator.id, 'available');
      }

      return { cancelled: true, strikes: 3 };
    }

    // Notify worker about the strike
    if (booking.operator?.id) {
      await this.notificationsService.sendToUser(booking.operator.id, {
        title: 'GPS Warning!',
        body: `You received strike ${booking.gpsStrikes}/3. Please head to the service location or the job will be forfeited.`,
      });
    }

    return { cancelled: false, strikes: booking.gpsStrikes };
  }

  async getBookingById(id: string): Promise<Booking | null> {
    return this.bookingsRepository
      .createQueryBuilder('booking')
      .leftJoinAndSelect('booking.customer', 'customer')
      .leftJoinAndSelect('booking.operator', 'operator')
      .where('booking.id = :id', { id })
      .getOne();
  }

  // ─── OTP GATE 1: ARRIVAL ──────────────────────────────────

  async verifyArrivalOtp(bookingId: string, otp: string): Promise<{ message: string; status: string }> {
    const booking = await this.bookingsRepository.findOne({ where: { id: bookingId } });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.arrivalOtp || booking.arrivalOtp !== otp) {
      throw new BadRequestException('Invalid arrival OTP');
    }

    // Clean up used OTP in redis just in case it exists to be tidy
    this.redisService.deleteOtp(`otp:booking:${bookingId}:arrival`).catch(() => {});

    // Transition: ACCEPTED → ACTIVE (worker has arrived, job begins)
    booking.status = BookingStatus.ACTIVE;
    booking.startedAt = new Date();
    await this.bookingsRepository.save(booking);

    return { message: 'Arrival confirmed. Job is now active.', status: 'ACTIVE' };
  }

  async verifyCompletionOtp(bookingId: string, otp: string): Promise<{ message: string; status: string; billingHours: number }> {
    const booking = await this.bookingsRepository.findOne({ where: { id: bookingId }, relations: ['operator'] });
    if (!booking) throw new NotFoundException('Booking not found');

    if (!booking.completionOtp || booking.completionOtp !== otp) {
      throw new BadRequestException('Invalid completion OTP');
    }

    // Clean up used OTP in redis just in case it exists to be tidy
    this.redisService.deleteOtp(`otp:booking:${bookingId}:completion`).catch(() => {});

    if (booking.status !== BookingStatus.ACTIVE) {
      throw new BadRequestException('Job must be active to complete');
    }

    // Calculate billing hours
    const startTime = booking.startedAt ? new Date(booking.startedAt).getTime() : Date.now();
    const endTime = Date.now();
    const hoursWorked = Math.max(1, Math.ceil((endTime - startTime) / (1000 * 60 * 60)));

    // Transition: ACTIVE → COMPLETED
    booking.status = BookingStatus.COMPLETED;
    booking.completedAt = new Date();
    booking.billingHours = hoursWorked;
    await this.bookingsRepository.save(booking);

    // Mark worker as available in Redis again
    if (booking.operator?.id) {
      await this.workersService.setWorkerStatus(booking.operator.id, 'available');
    }

    // DEFECT-003 FIX: Credit Rs.12 first-job bonus and set isFirstJobDone
    if (booking.operator?.id) {
      const workerProfile = await this.workerProfileRepo.findOne({
        where: { user: { id: booking.operator.id } },
      });
      if (workerProfile && !workerProfile.isFirstJobDone) {
        await this.walletsService.addFunds(booking.operator.id, 12);
        workerProfile.isFirstJobDone = true;
        await this.workerProfileRepo.save(workerProfile);
      }
    }

    return {
      message: 'Job completed successfully.',
      status: 'COMPLETED',
      billingHours: hoursWorked,
    };
  }

  async refreshCompletionOtp(bookingId: string): Promise<{ message: string; completionOtp: string }> {
    const booking = await this.bookingsRepository.findOne({
      where: { id: bookingId },
      relations: ['customer'],
    });
    if (!booking) throw new NotFoundException('Booking not found');

    const newOtp = this.generateOtp();
    booking.completionOtp = newOtp;
    await this.bookingsRepository.save(booking);

    // Also update Redis for consistency (though we now verify against DB primarily)
    await this.redisService.saveOtp(`otp:booking:${bookingId}:completion`, newOtp);

    // Notify customer
    if (booking.customer?.id) {
      await this.notificationsService.sendToUser(booking.customer.id, {
        title: 'New Completion OTP',
        body: `Your new completion OTP is: ${newOtp}`,
      });
    }

    return { message: 'Completion OTP refreshed', completionOtp: newOtp };
  }

  async findAllByUser(userId: string, role: 'customer' | 'operator'): Promise<Booking[]> {
    return this.bookingsRepository.find({
      where: role === 'customer' ? { customer: { id: userId } } : { operator: { id: userId } },
      relations: ['customer', 'operator'],
      order: { scheduledAt: 'DESC' },
    });
  }

  async findPendingForWorker(workerId: string): Promise<Booking[]> {
    // 1. Try Redis discovery first
    const ids = await this.redisService.getPendingBookingIds(workerId);
    
    if (ids.length > 0) {
      const bookings = await this.bookingsRepository.find({
        where: ids.map(id => ({ id })),
        relations: ['customer', 'operator']
      });
      // Ensure we preserve Redis order (DESC)
      return bookings.sort((a, b) => ids.indexOf(a.id) - ids.indexOf(b.id));
    }

    // 2. Fallback to DB query if Redis is empty or cold
    const dbBookings = await this.bookingsRepository.find({
      where: { operator: { id: workerId }, status: BookingStatus.REQUESTED },
      relations: ['customer', 'operator'],
      order: { createdAt: 'DESC' },
    });

    // 3. Re-populate Redis if we found some in DB
    if (dbBookings.length > 0) {
      for (const b of dbBookings) {
        await this.redisService.addPendingBooking(workerId, b.id);
      }
    }

    return dbBookings;
  }
}
