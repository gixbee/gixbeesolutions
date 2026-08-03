import { BadRequestException } from '@nestjs/common';
import { BookingCancelService } from './booking-cancel.service';
import { BookingStatus } from './booking.entity';
import { OutboxEventType } from '../outbox/outbox.types';

/**
 * Unit tests for the cancelBooking refund policy:
 * - unpaid booking            → nothing to refund (NONE)
 * - paid WALLET booking       → settlement reversed (worker debit + customer credit)
 * - paid CASH/UPI (markPaid)  → Gixbee never held the money → no wallet credit (DIRECT)
 * - completed booking         → cannot be cancelled
 * - outbox BOOKING_CANCELLED appended in the same transaction as the save
 */
function makeService(booking: any) {
  const bookingsRepository: any = {
    findOne: jest.fn(async () => booking),
    save: jest.fn(async (b: any) => b),
  };
  const workerProfileRepo: any = { findOne: jest.fn(), save: jest.fn() };
  const walletsService: any = {
    reverseBookingTransfer: jest.fn(async () => undefined),
    transferForBooking: jest.fn(async () => undefined),
    addFunds: jest.fn(async () => 0),
    deductBookingFee: jest.fn(async () => undefined),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
    sendToUsers: jest.fn(async () => undefined),
  };
  const redisService: any = {
    removePendingBooking: jest.fn(async () => undefined),
    cacheBookingStatus: jest.fn(async () => undefined),
    get: jest.fn(async () => null),
    set: jest.fn(async () => undefined),
    del: jest.fn(async () => undefined),
  };
  const jobCreditsService: any = {
    refundCredit: jest.fn(async () => undefined),
    consumeCredit: jest.fn(async () => 5),
  };
  const masterEntriesService: any = {
    getConfigNumber: jest.fn(async (_k: string, fallback: number) => fallback),
  };

  const manager: any = {
    save: jest.fn(async (b: any) => b),
    createQueryBuilder: jest.fn(() => {
      const qb: any = {
        setLock: jest.fn(() => qb),
        where: jest.fn(() => qb),
        getOne: jest.fn(async () => booking),
      };
      return qb;
    }),
    findOne: jest.fn(async () => booking),
    getRepository: jest.fn(() => ({
      findOne: jest.fn(async () => ({
        id: 'cust-1',
        lateCancelStrikeCount: 0,
        instantHelpBlocked: false,
      })),
      save: jest.fn(async (u: any) => u),
    })),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
    getRepository: jest.fn(() => ({
      findOne: jest.fn(async () => null),
      save: jest.fn(async (u: any) => u),
    })),
  };
  const outboxService: any = {
    append: jest.fn(
      async (_m: any, type: string, aggregateId: string, payload: any) => ({
        id: 'outbox-cancel-1',
        type,
        aggregateId,
        payload,
      }),
    ),
    enqueueDispatch: jest.fn(async () => undefined),
  };
  const bookingStatusService: any = {
    cacheAndEmitBookingStatus: jest.fn(async () => undefined),
  };

  const service = new BookingCancelService(
    bookingsRepository,
    workerProfileRepo,
    walletsService,
    notificationsService,
    redisService,
    dataSource,
    outboxService,
    jobCreditsService,
    masterEntriesService,
    bookingStatusService,
  );
  return {
    service,
    bookingsRepository,
    walletsService,
    manager,
    outboxService,
    redisService,
    notificationsService,
    jobCreditsService,
    bookingStatusService,
  };
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

describe('BookingCancelService.cancelBooking refund policy', () => {
  it('refunds nothing on an unpaid booking and appends cancel outbox', async () => {
    const booking = baseBooking();
    const { service, walletsService, manager, outboxService, redisService } =
      makeService(booking);

    const res = await service.cancelBooking('b1', 'Change of plans');

    expect(res.status).toBe('CANCELLED');
    expect(res.refundAmount).toBe(0);
    expect(res.refundMethod).toBe('NONE');
    expect(walletsService.reverseBookingTransfer).not.toHaveBeenCalled();
    expect(walletsService.addFunds).not.toHaveBeenCalled();
    expect(booking.status).toBe(BookingStatus.CANCELLED);
    expect((booking as any).cancellationReason).toBe('Change of plans');
    expect(manager.save).toHaveBeenCalledWith(booking);
    expect(outboxService.append).toHaveBeenCalledWith(
      manager,
      OutboxEventType.BOOKING_CANCELLED,
      'b1',
      expect.objectContaining({
        source: 'customer',
        reason: 'Change of plans',
      }),
    );
    expect(outboxService.enqueueDispatch).toHaveBeenCalledWith(
      'outbox-cancel-1',
    );
    expect(redisService.removePendingBooking).not.toHaveBeenCalled();
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
    const { service, outboxService } = makeService(booking);

    await expect(service.cancelBooking('b1', 'reason')).rejects.toThrow(
      BadRequestException,
    );
    expect(outboxService.append).not.toHaveBeenCalled();
  });
});
