import { BadRequestException } from '@nestjs/common';
import { WalletsService } from './wallets.service';
import { TransactionType } from './wallet-transaction.entity';

type MockUser = { id: string; walletBalance: number };

/**
 * Unit tests for the wallet money-movement primitives:
 * - transferForBooking  (completion settlement: customer → worker)
 * - reverseBookingTransfer (cancellation clawback: worker → customer)
 *
 * The DataSource transaction is mocked with an in-memory EntityManager so
 * the balance arithmetic and the recorded transaction pairs are asserted
 * without a database.
 */
function makeService(users: Record<string, MockUser>) {
  const saved: any[] = [];
  const manager = {
    findOne: jest.fn(
      async (_entity: any, opts: any) => users[opts.where.id] ?? null,
    ),
    create: jest.fn((_entity: any, dto: any) => dto),
    save: jest.fn(async (entityOrDto: any) => {
      saved.push(entityOrDto);
      return entityOrDto;
    }),
  };
  const usersRepository: any = {
    findOne: jest.fn(async ({ where: { id } }: any) => users[id] ?? null),
    save: jest.fn(async (u: any) => u),
  };
  const transactionsRepository: any = {
    create: jest.fn((dto: any) => dto),
    save: jest.fn(async (t: any) => t),
    find: jest.fn(async () => []),
  };
  const dataSource: any = {
    transaction: jest.fn(async (cb: any) => cb(manager)),
  };
  const service = new WalletsService(
    usersRepository,
    transactionsRepository,
    dataSource,
  );
  return { service, saved, dataSource };
}

describe('WalletsService.transferForBooking', () => {
  it('debits the customer, credits the worker, and records a DEBIT+CREDIT pair', async () => {
    const customer = { id: 'cust-1', walletBalance: 100 };
    const worker = { id: 'work-1', walletBalance: 10 };
    const { service, saved } = makeService({
      'cust-1': customer,
      'work-1': worker,
    });

    await service.transferForBooking(
      'cust-1',
      'work-1',
      40,
      'booking-12345678',
    );

    expect(customer.walletBalance).toBe(60);
    expect(worker.walletBalance).toBe(50);

    const txns = saved.filter((s) => s.type !== undefined);
    expect(txns).toHaveLength(2);
    expect(txns[0]).toMatchObject({
      user: customer,
      amount: 40,
      type: TransactionType.DEBIT,
    });
    expect(txns[0].description).toContain('Service payment');
    expect(txns[1]).toMatchObject({
      user: worker,
      amount: 40,
      type: TransactionType.CREDIT,
    });
    expect(txns[1].description).toContain('Service earnings');
  });

  it('throws on insufficient customer balance and moves no money', async () => {
    const customer = { id: 'cust-1', walletBalance: 10 };
    const worker = { id: 'work-1', walletBalance: 0 };
    const { service, saved } = makeService({
      'cust-1': customer,
      'work-1': worker,
    });

    await expect(
      service.transferForBooking('cust-1', 'work-1', 40, 'b1'),
    ).rejects.toThrow(BadRequestException);
    expect(customer.walletBalance).toBe(10);
    expect(worker.walletBalance).toBe(0);
    expect(saved).toHaveLength(0);
  });

  it('is a no-op for non-positive amounts', async () => {
    const { service, dataSource } = makeService({});
    await service.transferForBooking('cust-1', 'work-1', 0, 'b1');
    await service.transferForBooking('cust-1', 'work-1', -5, 'b1');
    expect(dataSource.transaction).not.toHaveBeenCalled();
  });

  it('rejects transfers to the same user', async () => {
    const { service } = makeService({});
    await expect(
      service.transferForBooking('u1', 'u1', 40, 'b1'),
    ).rejects.toThrow(BadRequestException);
  });
});

describe('WalletsService.reverseBookingTransfer', () => {
  it('claws the credit back from the worker and refunds the customer', async () => {
    const customer = { id: 'cust-1', walletBalance: 60 };
    const worker = { id: 'work-1', walletBalance: 50 };
    const { service, saved } = makeService({
      'cust-1': customer,
      'work-1': worker,
    });

    await service.reverseBookingTransfer(
      'cust-1',
      'work-1',
      40,
      'booking-12345678',
    );

    expect(worker.walletBalance).toBe(10);
    expect(customer.walletBalance).toBe(100);

    const txns = saved.filter((s) => s.type !== undefined);
    expect(txns).toHaveLength(2);
    expect(txns[0]).toMatchObject({
      user: worker,
      amount: 40,
      type: TransactionType.DEBIT,
    });
    expect(txns[0].description).toContain('Earnings reversal');
    expect(txns[1]).toMatchObject({
      user: customer,
      amount: 40,
      type: TransactionType.CREDIT,
    });
    expect(txns[1].description).toContain('Refund');
  });

  it('allows the worker balance to go negative so the customer is made whole', async () => {
    const customer = { id: 'cust-1', walletBalance: 0 };
    const worker = { id: 'work-1', walletBalance: 5 };
    const { service } = makeService({ 'cust-1': customer, 'work-1': worker });

    await service.reverseBookingTransfer('cust-1', 'work-1', 40, 'b1');

    expect(worker.walletBalance).toBe(-35);
    expect(customer.walletBalance).toBe(40);
  });

  it('is a no-op for non-positive amounts', async () => {
    const { service, dataSource } = makeService({});
    await service.reverseBookingTransfer('cust-1', 'work-1', 0, 'b1');
    expect(dataSource.transaction).not.toHaveBeenCalled();
  });

  it('rejects reversals to the same user', async () => {
    const { service } = makeService({});
    await expect(
      service.reverseBookingTransfer('u1', 'u1', 40, 'b1'),
    ).rejects.toThrow(BadRequestException);
  });
});
