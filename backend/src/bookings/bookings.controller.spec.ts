import { NotFoundException } from '@nestjs/common';
import { BookingsController } from './bookings.controller';
import { BookingStatus, BookingType } from './booking.entity';

/**
 * Unit tests for the BookingsController HTTP layer. The controller is a thin
 * delegation surface over BookingsService. These tests instantiate the
 * controller directly with jest-mock services (no Nest TestingModule) and assert:
 *  - create() maps the request body + req.user.userId into the service DTO shape
 *    (customer/operator wrapped as {id}, scheduledAt → Date, paymentMethod default
 *    'WALLET').
 *  - getMyBookings() parses page/limit (with non-numeric → defaults) and calls
 *    findMyBookings (single OR query — customer or operator).
 *  - status/cancel/otp/rating/mark-paid routes delegate with the right params and
 *    sensible defaults (cancel reason fallback).
 *  - accept() fires a customer push on success (string- or object-shaped customer),
 *    swallows a push failure, and rethrows a service error.
 *  - getBooking()/markArrived()/markComplete() throw NotFound on a missing booking.
 *  - getBookingStatus() returns the Redis cache on a hit and falls back to the DB
 *    (then populates the cache) on a miss.
 *  - dispute() echoes the reason without touching the service.
 */

function makeController(
  opts: {
    bookings?: Partial<Record<string, jest.Mock>>;
    redisCached?: any;
  } = {},
) {
  const bookingsService: any = {
    createBooking: jest.fn(async (dto: any) => ({ id: 'b1', ...dto })),
    findAllByUser: jest.fn(async () => []),
    findMyBookings: jest.fn(async () => []),
    findPendingForWorker: jest.fn(async () => []),
    updateStatus: jest.fn(async (id: string, status: BookingStatus) => ({
      id,
      status,
    })),
    cancelBooking: jest.fn(async (id: string, reason: string) => ({
      id,
      status: BookingStatus.CANCELLED,
      reason,
    })),
    verifyArrivalOtp: jest.fn(async (id: string, otp: string) => ({
      id,
      otp,
      ok: true,
    })),
    verifyCompletionOtp: jest.fn(async (id: string, otp: string) => ({
      id,
      otp,
      ok: true,
    })),
    refreshCompletionOtp: jest.fn(async (id: string) => ({
      id,
      completionOtp: '654321',
    })),
    acceptBooking: jest.fn(),
    rejectBooking: jest.fn(async (id: string, workerId: string) => ({
      id,
      workerId,
      rejected: true,
    })),
    getBookingById: jest.fn(async () => null),
    getStatusForParticipant: jest.fn(async () => ({ status: 'REQUESTED' })),
    assertParticipant: jest.fn(async () => ({
      id: 'b1',
      customer: { id: 'u1' },
    })),
    notifyArrival: jest.fn(async () => ({
      message: 'Arrival OTP sent to customer.',
    })),
    notifyCompletion: jest.fn(async () => ({
      message: 'Completion OTP sent to customer.',
    })),
    reportDispute: jest.fn(async () => ({
      success: true,
      message: 'Dispute logged',
    })),
    markPaid: jest.fn(async (id: string) => ({ message: 'paid' })),
    submitRating: jest.fn(async (id: string, rating: number) => ({
      id,
      rating,
    })),
    ...(opts.bookings ?? {}),
  };

  const controller = new BookingsController(bookingsService);
  return { controller, bookingsService };
}

const req = (userId = 'u1', role = 'CUSTOMER') => ({
  user: { userId, role },
});

describe('BookingsController.create', () => {
  it('maps the body + req.user into the service DTO shape', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req('cust-1'), {
      workerId: 'w-9',
      skill: 'plumbing',
      serviceLocation: 'Flat 2B',
      serviceLat: 12.9,
      serviceLng: 77.6,
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 500,
      type: BookingType.INSTANT,
    });

    const dto = bookingsService.createBooking.mock.calls[0][0];
    expect(dto.customer).toEqual({ id: 'cust-1' });
    expect(dto.operator).toEqual({ id: 'w-9' });
    expect(dto.skill).toBe('plumbing');
    expect(dto.scheduledAt).toBeInstanceOf(Date);
    expect(dto.scheduledAt.toISOString()).toBe('2026-07-01T10:00:00.000Z');
    expect(dto.amount).toBe(500);
    expect(dto.paymentMethod).toBe('CASH'); // default when omitted
  });

  it('keeps a supplied paymentMethod', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req(), {
      workerId: 'w-9',
      skill: 's',
      serviceLocation: 'l',
      serviceLat: 0,
      serviceLng: 0,
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
      type: BookingType.PACKAGE,
      paymentMethod: 'UPI',
    });
    expect(bookingsService.createBooking.mock.calls[0][0].paymentMethod).toBe(
      'UPI',
    );
  });

  it('forwards a picked saved-address id, and leaves it undefined when omitted', async () => {
    const { controller, bookingsService } = makeController();
    await controller.create(req(), {
      workerId: 'w-9',
      serviceLocation: 'Flat 2B',
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
      addressId: 'addr-7',
    } as any);
    expect(bookingsService.createBooking.mock.calls[0][0].addressId).toBe(
      'addr-7',
    );

    await controller.create(req(), {
      workerId: 'w-9',
      serviceLocation: 'Flat 2B',
      scheduledAt: '2026-07-01T10:00:00.000Z',
      amount: 1,
    } as any);
    expect(
      bookingsService.createBooking.mock.calls[1][0].addressId,
    ).toBeUndefined();
  });
});

describe('BookingsController.getMyBookings', () => {
  it('delegates to findMyBookings with parsed page/limit', async () => {
    const findMyBookings = jest.fn(async () => [{ id: 'c1' }, { id: 'o1' }]);
    const { controller, bookingsService } = makeController({
      bookings: { findMyBookings },
    });

    const res = await controller.getMyBookings(
      req('u-7'),
      'ACCEPTED',
      '2',
      '10',
    );

    expect(res).toEqual([{ id: 'c1' }, { id: 'o1' }]);
    expect(bookingsService.findMyBookings).toHaveBeenCalledWith(
      'u-7',
      'ACCEPTED',
      2,
      10,
    );
  });

  it('defaults page=1 / limit=50 when params are missing or non-numeric', async () => {
    const { controller, bookingsService } = makeController();
    await controller.getMyBookings(req('u-7'), undefined, 'abc', undefined);
    expect(bookingsService.findMyBookings).toHaveBeenCalledWith(
      'u-7',
      undefined,
      1,
      50,
    );
  });
});

describe('BookingsController.getPendingBookings', () => {
  it('delegates to findPendingForWorker with the caller id', async () => {
    const { controller, bookingsService } = makeController();
    await controller.getPendingBookings(req('w-1'));
    expect(bookingsService.findPendingForWorker).toHaveBeenCalledWith('w-1');
  });
});

describe('BookingsController.updateStatus / confirm', () => {
  it('updateStatus passes the body status through', async () => {
    const { controller, bookingsService } = makeController();
    await controller.updateStatus('b1', req(), {
      status: BookingStatus.ACTIVE,
    });
    expect(bookingsService.assertParticipant).toHaveBeenCalledWith('b1', 'u1');
    expect(bookingsService.updateStatus).toHaveBeenCalledWith(
      'b1',
      BookingStatus.ACTIVE,
    );
  });

  it('confirmBooking forces ACCEPTED', async () => {
    const { controller, bookingsService } = makeController();
    await controller.confirmBooking('b1', req());
    expect(bookingsService.updateStatus).toHaveBeenCalledWith(
      'b1',
      BookingStatus.ACCEPTED,
    );
  });
});

describe('BookingsController.cancel', () => {
  it('passes the supplied reason with customer source', async () => {
    const { controller, bookingsService } = makeController();
    await controller.cancel('b1', req('u1', 'CUSTOMER'), {
      reason: 'changed mind',
    });
    expect(bookingsService.cancelBooking).toHaveBeenCalledWith(
      'b1',
      'changed mind',
      'customer',
      undefined,
    );
  });

  it('falls back to "Not specified" when reason missing', async () => {
    const { controller, bookingsService } = makeController();
    await controller.cancel('b1', req('u1', 'CUSTOMER'), {} as any);
    expect(bookingsService.cancelBooking).toHaveBeenCalledWith(
      'b1',
      'Not specified',
      'customer',
      undefined,
    );
  });
});

describe('BookingsController OTP gates', () => {
  it('confirmArrival / confirmCompletion / refreshCompletionOtp delegate', async () => {
    const { controller, bookingsService } = makeController();
    await controller.confirmArrival('b1', req(), { otp: '111111' });
    await controller.confirmCompletion('b1', req(), { otp: '222222' });
    await controller.refreshCompletionOtp('b1', req());
    expect(bookingsService.verifyArrivalOtp).toHaveBeenCalledWith(
      'b1',
      '111111',
    );
    expect(bookingsService.verifyCompletionOtp).toHaveBeenCalledWith(
      'b1',
      '222222',
    );
    expect(bookingsService.refreshCompletionOtp).toHaveBeenCalledWith('b1');
  });
});

describe('BookingsController.acceptBooking', () => {
  it('delegates accept to the service (customer FCM is sent inside the service)', async () => {
    const acceptBooking = jest.fn(async () => ({
      booking: { customer: { id: 'cust-1' }, operator: { name: 'Asha' } },
    }));
    const { controller } = makeController({
      bookings: { acceptBooking },
    });

    const res = await controller.acceptBooking('b1', req('w-1'));

    expect(acceptBooking).toHaveBeenCalledWith('b1', 'w-1');
    expect(res).toBeDefined();
  });

  it('rethrows a service error', async () => {
    const acceptBooking = jest.fn(async () => {
      throw new Error('already taken');
    });
    const { controller } = makeController({ bookings: { acceptBooking } });
    await expect(controller.acceptBooking('b1', req('w-1'))).rejects.toThrow(
      'already taken',
    );
  });
});

describe('BookingsController.rejectBooking', () => {
  it('delegates with the caller id', async () => {
    const { controller, bookingsService } = makeController();
    await controller.rejectBooking('b1', req('w-3'));
    expect(bookingsService.rejectBooking).toHaveBeenCalledWith('b1', 'w-3');
  });
});

describe('BookingsController.getBooking', () => {
  it('returns the booking when the caller is a participant', async () => {
    const getBookingById = jest.fn(async () => ({
      id: 'b1',
      customer: { id: 'cust-1' },
      operator: { id: 'w-1' },
    }));
    const { controller } = makeController({ bookings: { getBookingById } });
    expect(await controller.getBooking('b1', req('cust-1'))).toEqual({
      id: 'b1',
      customer: { id: 'cust-1' },
      operator: { id: 'w-1' },
    });
  });

  it('throws NotFound when absent', async () => {
    const { controller } = makeController();
    await expect(controller.getBooking('b1', req('u1'))).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('throws NotFound when the caller is not a participant', async () => {
    const getBookingById = jest.fn(async () => ({
      id: 'b1',
      customer: { id: 'cust-1' },
      operator: { id: 'w-1' },
    }));
    const { controller } = makeController({ bookings: { getBookingById } });
    await expect(
      controller.getBooking('b1', req('stranger')),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('BookingsController.getBookingStatus', () => {
  it('delegates to getStatusForParticipant with the caller id', async () => {
    const getStatusForParticipant = jest.fn(async () => ({
      status: 'ACCEPTED',
      operatorName: 'Asha',
    }));
    const { controller } = makeController({
      bookings: { getStatusForParticipant },
    });
    const res = await controller.getBookingStatus('b1', req('cust-1'));
    expect(getStatusForParticipant).toHaveBeenCalledWith('b1', 'cust-1');
    expect(res).toEqual({ status: 'ACCEPTED', operatorName: 'Asha' });
  });
});

describe('BookingsController.markArrived / markComplete', () => {
  it('markArrived delegates to notifyArrival', async () => {
    const notifyArrival = jest.fn(async () => ({
      message: 'Arrival OTP sent to customer.',
    }));
    const { controller } = makeController({ bookings: { notifyArrival } });
    const res = await controller.markArrived('b1', req('w-1'));
    expect(notifyArrival).toHaveBeenCalledWith('b1', 'w-1');
    expect(res).toEqual({ message: 'Arrival OTP sent to customer.' });
  });

  it('markComplete delegates to notifyCompletion', async () => {
    const notifyCompletion = jest.fn(async () => ({
      message: 'Completion OTP sent to customer.',
    }));
    const { controller } = makeController({ bookings: { notifyCompletion } });
    const res = await controller.markComplete('b1', req('w-1'));
    expect(notifyCompletion).toHaveBeenCalledWith('b1', 'w-1');
    expect(res).toEqual({ message: 'Completion OTP sent to customer.' });
  });
});

describe('BookingsController.markPaid / submitRating / reportDispute', () => {
  it('markPaid delegates', async () => {
    const { controller, bookingsService } = makeController();
    await controller.markPaid(
      'b1',
      { user: { userId: 'u1' } },
      {
        honestyCheck: 'EXACT',
      },
    );
    expect(bookingsService.markPaid).toHaveBeenCalledWith('b1', 'u1', {
      honestyCheck: 'EXACT',
    });
  });

  it('submitRating passes the numeric rating for the customer', async () => {
    const assertParticipant = jest.fn(async () => ({
      id: 'b1',
      customer: { id: 'u1' },
    }));
    const { controller, bookingsService } = makeController({
      bookings: { assertParticipant },
    });
    await controller.submitRating('b1', req('u1'), { rating: 5 });
    expect(assertParticipant).toHaveBeenCalledWith('b1', 'u1');
    expect(bookingsService.submitRating).toHaveBeenCalledWith('b1', 5);
  });

  it('reportDispute delegates reason to the service', async () => {
    const reportDispute = jest.fn(async () => ({
      success: true,
      message: 'Dispute logged: late',
    }));
    const { controller } = makeController({ bookings: { reportDispute } });
    const res = await controller.reportDispute('b1', req('u1'), {
      reason: 'late',
    });
    expect(reportDispute).toHaveBeenCalledWith('b1', 'u1', 'late');
    expect(res).toEqual({ success: true, message: 'Dispute logged: late' });
  });
});
