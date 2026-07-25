import { OutboxService } from './outbox.service';
import { OutboxStatus } from './outbox-event.entity';
import { OutboxEventType } from './outbox.types';

describe('OutboxService.append', () => {
  it('creates and saves a pending row via the transaction manager', async () => {
    const saved = { id: 'e1', type: OutboxEventType.BOOKING_ACCEPTED };
    const manager: any = {
      create: jest.fn((_cls: any, data: any) => data),
      save: jest.fn(async (row: any) => ({ ...row, id: 'e1' })),
    };
    const repo: any = {};
    const queue: any = { add: jest.fn() };
    const service = new OutboxService(repo, queue);

    const result = await service.append(
      manager,
      OutboxEventType.BOOKING_ACCEPTED,
      'b1',
      { bookingId: 'b1' },
    );

    expect(manager.create).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        type: OutboxEventType.BOOKING_ACCEPTED,
        aggregateId: 'b1',
        status: OutboxStatus.PENDING,
        attempts: 0,
      }),
    );
    expect(manager.save).toHaveBeenCalled();
    expect(result.id).toBe('e1');
    expect(saved.id).toBe('e1');
  });

  it('enqueueDispatch adds a named job (duplicates are non-fatal)', async () => {
    const repo: any = {};
    const queue: any = {
      add: jest.fn(async () => undefined),
    };
    const service = new OutboxService(repo, queue);

    await service.enqueueDispatch('e1');

    expect(queue.add).toHaveBeenCalledWith(
      'dispatch',
      { eventId: 'e1' },
      expect.objectContaining({ jobId: 'outbox-dispatch:e1' }),
    );
  });
});
