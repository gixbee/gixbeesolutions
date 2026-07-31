import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, DataSource, In } from 'typeorm';
import { JobCredit } from './job-credit.entity';
import {
  CreditTransaction,
  CreditTransactionReason,
} from './credit-transaction.entity';
import { User } from '../users/user.entity';
import { Booking } from '../bookings/booking.entity';

export const CREDITS_PER_PACK = 3;
export const PACK_PRICE_INR = 49;

@Injectable()
export class JobCreditsService {
  constructor(
    @InjectRepository(JobCredit)
    private jobCreditsRepo: Repository<JobCredit>,
    @InjectRepository(CreditTransaction)
    private creditTxRepo: Repository<CreditTransaction>,
    private dataSource: DataSource,
  ) {}

  async getBalance(userId: string): Promise<number> {
    return this.dataSource.transaction(async (manager) => {
      let credit = await manager.findOne(JobCredit, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!credit) {
        credit = manager.create(JobCredit, {
          user: { id: userId } as User,
          balance: 0,
        });
        await manager.save(credit);
      }

      return credit.balance;
    });
  }

  /**
   * Credit + debit history for the worker's "where did my credits go"
   * screen. Booking-linked rows (accept debits, cancel/no-show refunds)
   * are enriched with the booking's skill so entries read like history
   * ("Job accepted — AC Technician"), not raw UUIDs.
   */
  async getTransactions(
    userId: string,
    page = 1,
    limit = 50,
  ): Promise<
    Array<{
      id: string;
      delta: number;
      reason: CreditTransactionReason;
      bookingId: string | null;
      bookingSkill: string | null;
      createdAt: Date;
    }>
  > {
    const txs = await this.creditTxRepo.find({
      where: { user: { id: userId } },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    const bookingIds = [
      ...new Set(
        txs.map((t) => t.bookingId).filter((id): id is string => !!id),
      ),
    ];
    const skillById = new Map<string, string>();
    if (bookingIds.length > 0) {
      const bookings = await this.dataSource
        .getRepository(Booking)
        .find({ where: { id: In(bookingIds) }, select: ['id', 'skill'] });
      for (const b of bookings) skillById.set(b.id, b.skill);
    }

    return txs.map((t) => ({
      id: t.id,
      delta: t.delta,
      reason: t.reason,
      bookingId: t.bookingId ?? null,
      bookingSkill: t.bookingId ? (skillById.get(t.bookingId) ?? null) : null,
      createdAt: t.createdAt,
    }));
  }

  async addCredits(
    userId: string,
    count: number,
    options: { reason: CreditTransactionReason; razorpayPaymentId?: string },
  ): Promise<number> {
    return this.dataSource.transaction(async (manager) => {
      if (options.razorpayPaymentId) {
        const existingTx = await manager.findOne(CreditTransaction, {
          where: { razorpayPaymentId: options.razorpayPaymentId },
        });
        if (existingTx) {
          const c = await manager.findOne(JobCredit, {
            where: { user: { id: userId } },
          });
          return c ? c.balance : 0;
        }
      }

      let credit = await manager.findOne(JobCredit, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!credit) {
        credit = manager.create(JobCredit, {
          user: { id: userId } as User,
          balance: 0,
        });
      }

      credit.balance += count;
      await manager.save(credit);

      await manager.save(
        manager.create(CreditTransaction, {
          user: { id: userId } as User,
          delta: count,
          reason: options.reason,
          razorpayPaymentId: options.razorpayPaymentId,
        }),
      );

      return credit.balance;
    });
  }

  async consumeCredit(
    userId: string,
    bookingId: string,
    providedManager?: any,
  ): Promise<number> {
    const execute = async (manager: any) => {
      const credit = await manager.findOne(JobCredit, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!credit || credit.balance < 1) {
        throw new BadRequestException(
          'No job credits left. Buy a pack to continue.',
        );
      }

      credit.balance -= 1;
      await manager.save(credit);

      await manager.save(
        manager.create(CreditTransaction, {
          user: { id: userId } as User,
          delta: -1,
          reason: CreditTransactionReason.JOB_ACCEPTED,
          bookingId,
        }),
      );

      return credit.balance;
    };

    if (providedManager) {
      return await execute(providedManager);
    } else {
      return await this.dataSource.transaction(execute);
    }
  }

  async refundCredit(
    userId: string,
    bookingId: string,
    reason: CreditTransactionReason,
    providedManager?: any,
  ): Promise<void> {
    const execute = async (manager: any) => {
      // Idempotency check: did we already refund this bookingId with this reason?
      const existingRefund = await manager.findOne(CreditTransaction, {
        where: { user: { id: userId }, bookingId, reason },
      });
      if (existingRefund) {
        return; // Already refunded
      }

      let credit = await manager.findOne(JobCredit, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!credit) {
        credit = manager.create(JobCredit, {
          user: { id: userId } as User,
          balance: 0,
        });
      }

      credit.balance += 1;
      await manager.save(credit);

      await manager.save(
        manager.create(CreditTransaction, {
          user: { id: userId } as User,
          delta: 1,
          reason,
          bookingId,
        }),
      );
    };

    if (providedManager) {
      await execute(providedManager);
    } else {
      await this.dataSource.transaction(execute);
    }
  }
}
