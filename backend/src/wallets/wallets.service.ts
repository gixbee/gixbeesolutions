import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource } from 'typeorm';
import { User } from '../users/user.entity';
import {
  WalletTransaction,
  TransactionType,
} from './wallet-transaction.entity';

@Injectable()
export class WalletsService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    @InjectRepository(WalletTransaction)
    private transactionsRepository: Repository<WalletTransaction>,
    private dataSource: DataSource,
  ) {}

  async getBalance(userId: string): Promise<number> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found');
    return Number(user.walletBalance);
  }

  // AUDIT FIX: both mutations below were unlocked read-modify-write —
  // concurrent debits/credits could lose updates. They now run inside a DB
  // transaction with a pessimistic row lock, matching transferForBooking.

  async deductBookingFee(userId: string): Promise<void> {
    await this.dataSource.transaction(async (manager) => {
      const user = await manager
        .createQueryBuilder(User, 'user')
        .setLock('pessimistic_write')
        .where('user.id = :userId', { userId })
        .getOne();
      if (!user) throw new BadRequestException('User not found');

      const fee = 12;
      if (Number(user.walletBalance) < fee) {
        throw new BadRequestException('Insufficient wallet balance');
      }

      user.walletBalance = Number(user.walletBalance) - fee;
      await manager.save(user);

      await manager.save(
        this.transactionsRepository.create({
          user,
          amount: fee,
          type: TransactionType.DEBIT,
          description: 'Gixbee Service Fee (Booking)',
        }),
      );
    });
  }

  /**
   * Generic wallet debit with row lock — used by Smart Hiring fees
   * (job-preference ₹50/month, hiring-request tier pricing) and any future
   * flat charges. Throws on insufficient balance.
   */
  async charge(
    userId: string,
    amount: number,
    description: string,
  ): Promise<void> {
    if (amount <= 0) return;
    await this.dataSource.transaction(async (manager) => {
      const user = await manager
        .createQueryBuilder(User, 'user')
        .setLock('pessimistic_write')
        .where('user.id = :userId', { userId })
        .getOne();
      if (!user) throw new BadRequestException('User not found');
      if (Number(user.walletBalance) < amount) {
        throw new BadRequestException(
          `Insufficient wallet balance — ₹${amount} required. Please top up.`,
        );
      }
      user.walletBalance = Number(user.walletBalance) - amount;
      await manager.save(user);
      await manager.save(
        this.transactionsRepository.create({
          user,
          amount,
          type: TransactionType.DEBIT,
          description,
        }),
      );
    });
  }

  async addFunds(
    userId: string,
    amount: number,
    description = 'Wallet Recharge',
  ): Promise<number> {
    return this.dataSource.transaction(async (manager) => {
      const user = await manager
        .createQueryBuilder(User, 'user')
        .setLock('pessimistic_write')
        .where('user.id = :userId', { userId })
        .getOne();
      if (!user) throw new BadRequestException('User not found');

      user.walletBalance = Number(user.walletBalance) + amount;
      await manager.save(user);

      await manager.save(
        this.transactionsRepository.create({
          user,
          amount,
          type: TransactionType.CREDIT,
          description,
        }),
      );

      return Number(user.walletBalance);
    });
  }

  /**
   * Settle a WALLET booking payment atomically:
   * debit the customer's wallet, credit the worker's wallet, and record
   * a DEBIT + CREDIT transaction pair — all in one DB transaction with
   * row locks so concurrent settlements can't corrupt balances.
   *
   * Throws BadRequestException on insufficient customer balance; the
   * caller should fall back to direct collection (cash/UPI) in that case.
   */
  async transferForBooking(
    customerId: string,
    workerId: string,
    amount: number,
    bookingId: string,
  ): Promise<void> {
    if (amount <= 0) return;
    if (customerId === workerId) {
      throw new BadRequestException('Cannot transfer to the same user');
    }

    const ref = bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId;

    await this.dataSource.transaction(async (manager) => {
      // Lock both rows in a stable order (by id) to avoid deadlocks
      const [firstId, secondId] =
        customerId < workerId ? [customerId, workerId] : [workerId, customerId];
      await manager.findOne(User, {
        where: { id: firstId },
        lock: { mode: 'pessimistic_write' },
      });
      await manager.findOne(User, {
        where: { id: secondId },
        lock: { mode: 'pessimistic_write' },
      });

      const customer = await manager.findOne(User, {
        where: { id: customerId },
      });
      const worker = await manager.findOne(User, { where: { id: workerId } });
      if (!customer) throw new BadRequestException('Customer not found');
      if (!worker) throw new BadRequestException('Worker not found');

      const customerBalance = Number(customer.walletBalance);
      if (customerBalance < amount) {
        throw new BadRequestException('Insufficient wallet balance');
      }

      customer.walletBalance = customerBalance - amount;
      worker.walletBalance = Number(worker.walletBalance) + amount;
      await manager.save(customer);
      await manager.save(worker);

      await manager.save(
        manager.create(WalletTransaction, {
          user: customer,
          amount,
          type: TransactionType.DEBIT,
          description: `Service payment (Booking ${ref})`,
        }),
      );
      await manager.save(
        manager.create(WalletTransaction, {
          user: worker,
          amount,
          type: TransactionType.CREDIT,
          description: `Service earnings (Booking ${ref})`,
        }),
      );
    });
  }

  /**
   * Reverse a settled WALLET booking payment when the booking is
   * cancelled: debit the worker's wallet, credit the customer's wallet,
   * and record the reversal transaction pair — atomic, with the same
   * stable-order row locking as transferForBooking.
   *
   * The worker's balance is allowed to go negative here — intentional:
   * the credit is clawed back as a recorded debt rather than leaving the
   * customer short on a refund.
   */
  async reverseBookingTransfer(
    customerId: string,
    workerId: string,
    amount: number,
    bookingId: string,
  ): Promise<void> {
    if (amount <= 0) return;
    if (customerId === workerId) {
      throw new BadRequestException(
        'Cannot reverse a transfer to the same user',
      );
    }

    const ref = bookingId.length > 8 ? bookingId.substring(0, 8) : bookingId;

    await this.dataSource.transaction(async (manager) => {
      // Lock both rows in a stable order (by id) to avoid deadlocks
      const [firstId, secondId] =
        customerId < workerId ? [customerId, workerId] : [workerId, customerId];
      await manager.findOne(User, {
        where: { id: firstId },
        lock: { mode: 'pessimistic_write' },
      });
      await manager.findOne(User, {
        where: { id: secondId },
        lock: { mode: 'pessimistic_write' },
      });

      const customer = await manager.findOne(User, {
        where: { id: customerId },
      });
      const worker = await manager.findOne(User, { where: { id: workerId } });
      if (!customer) throw new BadRequestException('Customer not found');
      if (!worker) throw new BadRequestException('Worker not found');

      worker.walletBalance = Number(worker.walletBalance) - amount;
      customer.walletBalance = Number(customer.walletBalance) + amount;
      await manager.save(worker);
      await manager.save(customer);

      await manager.save(
        manager.create(WalletTransaction, {
          user: worker,
          amount,
          type: TransactionType.DEBIT,
          description: `Earnings reversal — booking cancelled (Booking ${ref})`,
        }),
      );
      await manager.save(
        manager.create(WalletTransaction, {
          user: customer,
          amount,
          type: TransactionType.CREDIT,
          description: `Refund — booking cancelled (Booking ${ref})`,
        }),
      );
    });
  }

  async getTransactions(
    userId: string,
    page = 1,
    limit = 50,
  ): Promise<WalletTransaction[]> {
    return this.transactionsRepository.find({
      where: { user: { id: userId } },
      order: { timestamp: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
  }
}
