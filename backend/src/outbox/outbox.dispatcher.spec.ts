import { OutboxDispatcher } from './outbox.dispatcher';
import { OutboxStatus } from './outbox-event.entity';
import { OutboxEventType } from './outbox.types';

describe('OutboxDispatcher.dispatchOne idempotency', () => {
  function makeDispatcher(opts: {
    event?: any;
    handleImpl?: () => Promise<void>;
  }) {
    const outboxService: any = {
      findById: jest.fn(async () => opts.event ?? null),
      markProcessed: jest.fn(async () => undefined),
      recordAttempt: jest.fn(async () => undefined),
      maxAttempts: 10,
      findDispatchable: jest.fn(async () => []),
    };
    const handler: any = {
      handle: jest.fn(opts.handleImpl ?? (async () => undefined)),
    };
    const systemLogs: any = { record: jest.fn() };
    const queue: any = { add: jest.fn() };
    const dispatcher = new OutboxDispatcher(
      outboxService,
      handler,
      systemLogs,
      queue,
    );
    return { dispatcher, outboxService, handler, systemLogs };
  }

  it('skips when the event is already processed', async () => {
    const { dispatcher, outboxService, handler } = makeDispatcher({
      event: {
        id: 'e1',
        status: OutboxStatus.PROCESSED,
        type: OutboxEventType.BOOKING_ACCEPTED,
        attempts: 1,
      },
    });

    const result = await dispatcher.dispatchOne('e1');

    expect(result).toBe('skipped');
    expect(handler.handle).not.toHaveBeenCalled();
    expect(outboxService.markProcessed).not.toHaveBeenCalled();
  });

  it('handles then marks processed on success', async () => {
    const event = {
      id: 'e1',
      status: OutboxStatus.PENDING,
      type: OutboxEventType.BOOKING_CANCELLED,
      attempts: 0,
      payload: { bookingId: 'b1' },
    };
    const { dispatcher, outboxService, handler, systemLogs } = makeDispatcher({
      event,
    });

    const result = await dispatcher.dispatchOne('e1');

    expect(result).toBe('processed');
    expect(handler.handle).toHaveBeenCalledWith(event);
    expect(outboxService.markProcessed).toHaveBeenCalledWith('e1');
    expect(systemLogs.record).not.toHaveBeenCalled();
  });

  it('records an attempt and writes a SYSTEM log on handler failure', async () => {
    const event = {
      id: 'e1',
      status: OutboxStatus.PENDING,
      type: OutboxEventType.BOOKING_ACCEPTED,
      attempts: 0,
      aggregateId: 'b1',
      payload: {},
    };
    const { dispatcher, outboxService, systemLogs } = makeDispatcher({
      event,
      handleImpl: async () => {
        throw new Error('FCM down');
      },
    });
    // After recordAttempt, findById still returns pending with attempts bumped.
    outboxService.findById.mockResolvedValueOnce(event).mockResolvedValueOnce({
      ...event,
      attempts: 1,
      status: OutboxStatus.PENDING,
    });

    const result = await dispatcher.dispatchOne('e1');

    expect(result).toBe('failed');
    expect(outboxService.markProcessed).not.toHaveBeenCalled();
    expect(outboxService.recordAttempt).toHaveBeenCalledWith('e1', 'FCM down');
    expect(systemLogs.record).toHaveBeenCalledWith(
      expect.objectContaining({
        level: 'ERROR',
        type: 'SYSTEM',
        message: expect.stringContaining('Outbox dispatch failed'),
      }),
    );
  });

  it('is safe to dispatch twice — second call skips after PROCESSED', async () => {
    let status = OutboxStatus.PENDING;
    const event = {
      id: 'e1',
      get status() {
        return status;
      },
      type: OutboxEventType.BOOKING_BROADCAST_CREATED,
      attempts: 0,
    };
    const outboxService: any = {
      findById: jest.fn(async () => event),
      markProcessed: jest.fn(async () => {
        status = OutboxStatus.PROCESSED;
      }),
      recordAttempt: jest.fn(),
      maxAttempts: 10,
    };
    const handler: any = { handle: jest.fn(async () => undefined) };
    const systemLogs: any = { record: jest.fn() };
    const dispatcher = new OutboxDispatcher(
      outboxService,
      handler,
      systemLogs,
      {
        add: jest.fn(),
      } as any,
    );

    expect(await dispatcher.dispatchOne('e1')).toBe('processed');
    expect(await dispatcher.dispatchOne('e1')).toBe('skipped');
    expect(handler.handle).toHaveBeenCalledTimes(1);
  });
});
