import { BookingLifecycleHandler } from './booking-lifecycle.handler';
import { OutboxEventType } from './outbox.types';
import { OutboxStatus } from './outbox-event.entity';

describe('BookingLifecycleHandler idempotency', () => {
  function makeHandler() {
    const notificationsService: any = {
      sendToUser: jest.fn(async () => undefined),
      sendToUsers: jest.fn(async () => undefined),
    };
    const redisService: any = {
      saveOtp: jest.fn(async () => undefined),
      cacheBookingStatus: jest.fn(async () => undefined),
      addPendingBooking: jest.fn(async () => undefined),
      removePendingBooking: jest.fn(async () => undefined),
      set: jest.fn(async () => undefined),
      get: jest.fn(async () => null),
      del: jest.fn(async () => undefined),
    };
    const workersService: any = {
      setWorkerStatus: jest.fn(async () => undefined),
      recordCompletedJobForPeriod: jest.fn(async () => undefined),
    };
    const messagesGateway: any = {
      emitUserEvent: jest.fn(),
    };
    const bookingsQueue: any = {
      add: jest.fn(async () => undefined),
    };
    const handler = new BookingLifecycleHandler(
      notificationsService,
      redisService,
      workersService,
      messagesGateway,
      bookingsQueue,
    );
    return {
      handler,
      notificationsService,
      redisService,
      workersService,
      messagesGateway,
      bookingsQueue,
    };
  }

  it('onAccepted can run twice without throwing (idempotent Redis/FCM)', async () => {
    const { handler, redisService, workersService, notificationsService } =
      makeHandler();
    const event: any = {
      id: 'e1',
      type: OutboxEventType.BOOKING_ACCEPTED,
      status: OutboxStatus.PENDING,
      payload: {
        bookingId: 'b1',
        workerId: 'work-1',
        customerId: 'cust-1',
        operatorName: 'Anu',
        arrivalOtp: '1111',
        cancelledBookingIds: [],
        cancelledCustomerIds: [],
      },
    };

    await handler.handle(event);
    await handler.handle(event);

    expect(workersService.setWorkerStatus).toHaveBeenCalledTimes(2);
    expect(redisService.removePendingBooking).toHaveBeenCalledTimes(2);
    expect(redisService.cacheBookingStatus).toHaveBeenCalledTimes(2);
    expect(notificationsService.sendToUser).toHaveBeenCalledTimes(2);
  });

  it('onCancelled timeout notifies the customer', async () => {
    const { handler, notificationsService } = makeHandler();
    await handler.handle({
      id: 'e2',
      type: OutboxEventType.BOOKING_CANCELLED,
      status: OutboxStatus.PENDING,
      payload: {
        bookingId: 'b1',
        reason: 'timeout',
        source: 'timeout',
        operatorId: null,
        operatorName: null,
        customerId: 'cust-1',
      },
    } as any);

    expect(notificationsService.sendToUser).toHaveBeenCalledWith(
      'cust-1',
      expect.objectContaining({ title: 'No Workers Available' }),
    );
  });

  it('onCompleted caches status, releases worker, and counts period fee', async () => {
    const { handler, redisService, workersService, messagesGateway } =
      makeHandler();
    const event: any = {
      id: 'e3',
      type: OutboxEventType.BOOKING_COMPLETED,
      status: OutboxStatus.PENDING,
      payload: {
        bookingId: 'b1',
        customerId: 'cust-1',
        operatorId: 'work-1',
        operatorName: 'Anu',
        isPaid: false,
        workerPaidConfirmed: false,
        customerPaidConfirmed: false,
      },
    };

    await handler.handle(event);
    await handler.handle(event);

    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({ status: 'COMPLETED', operatorId: 'work-1' }),
    );
    expect(workersService.setWorkerStatus).toHaveBeenCalledWith(
      'work-1',
      'available',
    );
    expect(workersService.recordCompletedJobForPeriod).toHaveBeenCalledWith(
      'work-1',
    );
    expect(messagesGateway.emitUserEvent).toHaveBeenCalled();
  });

  it('onPaymentConfirmed refreshes Redis/socket payment flags', async () => {
    const { handler, redisService } = makeHandler();
    await handler.handle({
      id: 'e4',
      type: OutboxEventType.BOOKING_PAYMENT_CONFIRMED,
      status: OutboxStatus.PENDING,
      payload: {
        bookingId: 'b1',
        customerId: 'cust-1',
        operatorId: 'work-1',
        operatorName: 'Anu',
        status: 'COMPLETED',
        isPaid: true,
        workerPaidConfirmed: true,
        customerPaidConfirmed: true,
      },
    } as any);

    expect(redisService.cacheBookingStatus).toHaveBeenCalledWith(
      'b1',
      expect.objectContaining({
        status: 'COMPLETED',
        isPaid: true,
        workerPaidConfirmed: true,
        customerPaidConfirmed: true,
      }),
    );
  });
});
