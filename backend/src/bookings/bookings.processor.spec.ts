import { BookingsProcessor } from './bookings.processor';
import { BookingStatus } from './booking.entity';

/**
 * Unit tests for BookingsProcessor — the Bull queue worker behind the
 * instant-booking lifecycle. It has three @Process handlers, each with real
 * branching that was previously untested:
 *   sevenMinuteReminder · tenMinuteGpsCheck · requestTimeout
 *
 * Direct-construction harness (no Nest TestingModule / no real Bull queue);
 * every collaborator is a plain jest mock so each test asserts exactly which
 * side effects fired. A fake Bull `Job` is just `{ data: { bookingId } }`.
 */
function makeProcessor() {
  const bookingsService: any = {
    getBookingById: jest.fn(async () => null),
    addGpsStrike: jest.fn(async () => ({ cancelled: false, strikes: 1 })),
    updateStatus: jest.fn(async () => undefined),
    calculateDistance: jest.fn(() => 0),
    evaluateWorkerProgress: jest.fn(() => ({
      progressing: true,
      reason: 'ok',
    })),
    rebroadcastBooking: jest.fn(async () => ({ stillOpen: true, notified: 0 })),
    timeoutCancelBooking: jest.fn(async () => ({ cancelled: true })),
  };
  const redisService: any = {
    getWorkerLocation: jest.fn(async () => null),
  };
  const notificationsService: any = {
    sendToUser: jest.fn(async () => undefined),
  };
  const workersService: any = {};
  const systemLogs: any = { record: jest.fn() };
  const bookingsQueue: any = { add: jest.fn(async () => undefined) };

  const processor = new BookingsProcessor(
    bookingsService,
    redisService,
    notificationsService,
    workersService,
    systemLogs,
    bookingsQueue,
  );
  // silence the Logger so test output stays clean
  jest
    .spyOn((processor as any).logger, 'log')
    .mockImplementation(() => undefined);
  jest
    .spyOn((processor as any).logger, 'warn')
    .mockImplementation(() => undefined);
  jest
    .spyOn((processor as any).logger, 'debug')
    .mockImplementation(() => undefined);

  return {
    processor,
    bookingsService,
    redisService,
    notificationsService,
    bookingsQueue,
  };
}

const job = (bookingId: any) => ({ data: { bookingId } }) as any;

describe('BookingsProcessor', () => {
  // ---- handleSevenMinuteReminder --------------------------------------
  describe('handleSevenMinuteReminder', () => {
    it('returns undefined and notifies no one when the booking is missing', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce(null);

      const res = await processor.handleSevenMinuteReminder(job('b1'));

      expect(res).toBeUndefined();
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });

    it('skips (no notify) when the booking is no longer ACCEPTED', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACTIVE,
        operator: { id: 'op1' },
      });

      const res = await processor.handleSevenMinuteReminder(job('b1'));

      expect(res).toEqual({ status: 'Skipped - Not ACCEPTED' });
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });

    it('notifies the operator and returns "Reminder Sent" when ACCEPTED', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: { id: 'op1' },
      });

      const res = await processor.handleSevenMinuteReminder(job('b1'));

      expect(res).toEqual({ status: 'Reminder Sent' });
      expect(notificationsService.sendToUser).toHaveBeenCalledWith(
        'op1',
        expect.objectContaining({ title: expect.stringContaining('Reminder') }),
      );
    });

    it('still returns "Reminder Sent" but skips notify when no operator is assigned', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: null,
      });

      const res = await processor.handleSevenMinuteReminder(job('b1'));

      expect(res).toEqual({ status: 'Reminder Sent' });
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });
  });

  // ---- handleTenMinuteGpsCheck ----------------------------------------
  describe('handleTenMinuteGpsCheck', () => {
    it('returns undefined when the booking is missing', async () => {
      const { processor, bookingsService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce(null);

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toBeUndefined();
      expect(bookingsService.addGpsStrike).not.toHaveBeenCalled();
    });

    it('stops monitoring when the booking is no longer ACCEPTED', async () => {
      const { processor, bookingsService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACTIVE,
        operator: { id: 'op1' },
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toEqual({
        status: 'Monitoring Stopped - Job Active or Cancelled',
      });
      expect(bookingsService.addGpsStrike).not.toHaveBeenCalled();
    });

    it('returns undefined when ACCEPTED but no operator is assigned', async () => {
      const { processor, bookingsService, redisService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: null,
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toBeUndefined();
      expect(redisService.getWorkerLocation).not.toHaveBeenCalled();
    });

    it('verifies progress (no strike) when evaluateWorkerProgress passes', async () => {
      const { processor, bookingsService, redisService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: { id: 'op1' },
        serviceLat: 12.9,
        serviceLng: 77.6,
        acceptDistanceKm: 2,
      });
      redisService.getWorkerLocation.mockResolvedValueOnce({
        lat: 12.91,
        lng: 77.61,
        timestamp: new Date().toISOString(),
      });
      bookingsService.evaluateWorkerProgress.mockReturnValueOnce({
        progressing: true,
        reason: 'Moved closer',
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toEqual({ status: 'GPS Verified' });
      expect(bookingsService.addGpsStrike).not.toHaveBeenCalled();
    });

    it('issues a strike and reschedules a 3-minute recheck when not progressing', async () => {
      const { processor, bookingsService, redisService, bookingsQueue } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: { id: 'op1' },
        serviceLat: 12.9,
        serviceLng: 77.6,
      });
      redisService.getWorkerLocation.mockResolvedValueOnce(null);
      bookingsService.evaluateWorkerProgress.mockReturnValueOnce({
        progressing: false,
        reason: 'No recent location update found.',
      });
      bookingsService.addGpsStrike.mockResolvedValueOnce({
        cancelled: false,
        strikes: 1,
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(bookingsService.addGpsStrike).toHaveBeenCalledWith('b1');
      expect(bookingsQueue.add).toHaveBeenCalledWith(
        'tenMinuteGpsCheck',
        { bookingId: 'b1' },
        { delay: 3 * 60 * 1000 },
      );
      expect(res).toEqual({
        status: 'Strike 1 issued. Rescheduled check in 3m.',
      });
    });

    it('stops rescheduling when free cancel is enabled', async () => {
      const { processor, bookingsService, redisService, bookingsQueue } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: { id: 'op1' },
        serviceLat: 12.9,
        serviceLng: 77.6,
      });
      redisService.getWorkerLocation.mockResolvedValueOnce(null);
      bookingsService.evaluateWorkerProgress.mockReturnValueOnce({
        progressing: false,
        reason: 'No recent location update found.',
      });
      bookingsService.addGpsStrike.mockResolvedValueOnce({
        cancelled: false,
        strikes: 2,
        freeCancelEnabled: true,
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toEqual({
        status: 'No progress — customer free cancel enabled (strike 2).',
      });
      expect(bookingsQueue.add).not.toHaveBeenCalled();
    });

    it('skips work when free cancel was already enabled', async () => {
      const { processor, bookingsService, redisService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        operator: { id: 'op1' },
        workerNoProgressAt: new Date(),
      });

      const res = await processor.handleTenMinuteGpsCheck(job('b1'));

      expect(res).toEqual({ status: 'Free cancel already enabled' });
      expect(redisService.getWorkerLocation).not.toHaveBeenCalled();
    });
  });

  // ---- handleRequestTimeout ------------------------------------------
  describe('handleRequestTimeout', () => {
    it('returns undefined when the booking is missing', async () => {
      const { processor, bookingsService } = makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce(null);

      const res = await processor.handleRequestTimeout(job('b1'));

      expect(res).toBeUndefined();
      expect(bookingsService.updateStatus).not.toHaveBeenCalled();
    });

    it('skips cancellation when the booking is no longer REQUESTED', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.ACCEPTED,
        customer: { id: 'c1' },
      });

      const res = await processor.handleRequestTimeout(job('b1'));

      expect(res).toEqual({ status: 'Skipped - Already accepted' });
      expect(bookingsService.updateStatus).not.toHaveBeenCalled();
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
    });

    it('auto-cancels via timeoutCancelBooking when still REQUESTED (FCM via outbox)', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.REQUESTED,
        customer: { id: 'c1' },
        operator: { id: 'op1' }, // targeted — skip rebroadcast wave
      });
      bookingsService.timeoutCancelBooking.mockResolvedValueOnce({
        cancelled: true,
      });

      const res = await processor.handleRequestTimeout(job('b1'));

      expect(bookingsService.timeoutCancelBooking).toHaveBeenCalledWith('b1');
      // Customer FCM is emitted by the BOOKING_CANCELLED outbox listener.
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
      expect(res).toEqual({ status: 'Cancelled - Timeout' });
    });

    it('auto-cancels when no customer id is present', async () => {
      const { processor, bookingsService, notificationsService } =
        makeProcessor();
      bookingsService.getBookingById.mockResolvedValueOnce({
        status: BookingStatus.REQUESTED,
        customer: null,
        operator: { id: 'op1' },
      });
      bookingsService.timeoutCancelBooking.mockResolvedValueOnce({
        cancelled: true,
      });

      const res = await processor.handleRequestTimeout(job('b1'));

      expect(bookingsService.timeoutCancelBooking).toHaveBeenCalledWith('b1');
      expect(notificationsService.sendToUser).not.toHaveBeenCalled();
      expect(res).toEqual({ status: 'Cancelled - Timeout' });
    });
  });
});
