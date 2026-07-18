import { BadRequestException } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingStatus } from './booking.entity';

/**
 * Unit tests for the cancelBooking refund policy:
 * - unpaid booking            → nothing to refund (NONE)
 * - paid WALLET booking       → settlement reversed (worker debit + customer credit)
 * - paid CASH/UPI (markPaid)  → Gixbee never held the money → no wallet credit (DIRECT)
 * - completed booking         → cannot be cancelled
 */
function makeService(booking: any) {
  const bookingsRepository: any = {
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
  };
  const workerProfileRepo: any = { findOne: jest.fn(), save: jest.fn() };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };
  const walletsService: any = {
    reverseBookingTransfer: jest.fn(async () => undefined),
    transferForBooking: jest.fn(async () => undefined),
    addFunds: jest.fn(async () => 0),
    deductBookingFee: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const redisService: any = {
    removePendingBooking: jest.fn(async () => undefined),
    cacheBookingStatus: jest.fn(async () => undefined),
  };
  const workersService: any = {
    setWorkerStatus: jest.fn(async () => undefined),
  };
  const dataSource: any = { transaction: jest.fn() };

  const service = new BookingsService(
    bookingsRepository,
    workerProfileRepo,
    bookingsQueue,
    walletsService,
    notificationsService,
    redisService,
    workersService,
    dataSource,
  );
  return { service, bookingsRepository, walletsService };
}

const baseBooking = () => ({
  id: 'b1',
  status: BookingStatus.ACCEPTED,
  isPaid: false,
  paymentMethod: 'WALLET',
  amount: 500,
  totalAmount: undefined as number | undefined,
  customer: { id: 'cust-1' },
  operator: { id: 'work-1' },
});

describe('BookingsService.cancelBooking refund policy', () => {
  it('refunds nothing on an unpaid booking', async () => {
    const booking = baseBooking();
    const { service, walletsService, bookingsRepository } = makeService(booking);

    const res = await service.cancelBooking('b1', 'Change of plans');

    expect(res.status).toBe('CANCELLED');
    expect(res.refundAmount).toBe(0);
    expect(res.refundMethod).toBe('NONE');
    expect(walletsService.reverseBookingTransfer).not.toHaveBeenCalled();
    expect(walletsService.addFunds).not.toHaveBeenCalled();
    expect(booking.status).toBe(BookingStatus.CANCELLED);
    expect((booking as any).cancellationReason).toBe('Change of plans');
    expect(bookingsRepository.save).toHaveBeenCalledWith(booking);
  });

  it('reverses the wallet settlement on a paid WALLET booking', async () => {
    const booking = { ...baseBooking(), isPaid: true, totalAmount: 500 };
    const { service, walletsService } = makeService(booking);

    const res = await service.cancelBooking('b1', 'reason');

    expect(walletsService.reverseBookingTransfer).toHaveBeenCalledWith(
      'cust-1',
      'work-1',
      500,
      'b1',
    );
    expect(res.refundAmount).toBe(500);
    expect(res.refundMethod).toBe('WALLET');
  });

  it('falls back to booking.amount when totalAmount is not set', async () => {
    const booking = {
      ...baseBooking(),
      isPaid: true,
      totalAmount: undefined,
      amount: 350,
    };
    const { service, walletsService } = makeService(booking);

    const res = await service.cancelBooking('b1', 'reason');

    expect(walletsService.reverseBookingTransfer).toHaveBeenCalledWith(
      'cust-1',
      'work-1',
      350,
      'b1',
    );
    expect(res.refundAmount).toBe(350);
  });

  it('does NOT mint a wallet credit for directly collected (CASH/UPI) payments', async () => {
    const booking = {
      ...baseBooking(),
      isPaid: true,
      paymentMethod: 'CASH',
      totalAmount: 500,
    };
    const { service, walletsService } = makeService(booking);

    const res = await service.cancelBooking('b1', 'reason');

    expect(walletsService.reverseBookingTransfer).not.toHaveBeenCalled();
    expect(walletsService.addFunds).not.toHaveBeenCalled();
    expect(res.refundAmount).toBe(0);
    expect(res.refundMethod).toBe('DIRECT');
    expect(res.message).toContain('collected directly');
  });

  it('refuses to cancel a completed booking', async () => {
    const booking = { ...baseBooking(), status: BookingStatus.COMPLETED };
    const { service } = makeService(booking);

    await expect(service.cancelBooking('b1', 'reason')).rejects.toThrow(
      BadRequestException,
    );
  });
});
