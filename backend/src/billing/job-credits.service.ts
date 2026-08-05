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
import { MasterEntriesService } from '../master-entries/master-entries.service';

export const CREDITS_PER_PACK = 3;
export const PACK_PRICE_INR = 49;

/** Master Entries CONFIGURATION key — admin-editable accept cost. */
export const JOB_CREDIT_PER_ACCEPT_KEY = 'job_credit_per_accept';
const JOB_CREDIT_PER_ACCEPT_FALLBACK = 15;

@Injectable()
export class JobCreditsService {
  constructor(
    @InjectRepository(JobCredit)
    private jobCreditsRepo: Repository<JobCredit>,
    @InjectRepository(CreditTransaction)
    private creditTxRepo: Repository<CreditTransaction>,
    private dataSource: DataSource,
    private masterEntriesService: MasterEntriesService,
  ) {}

  /**
   * Credits deducted on accept. From Master Entries
   * (`job_credit_per_accept`); fallback 1. Floored at 0 (0 = free accepts).
   */
  async getCreditsPerAccept(): Promise<number> {
    const raw = await this.masterEntriesService.getConfigNumber(
      JOB_CREDIT_PER_ACCEPT_KEY,
      JOB_CREDIT_PER_ACCEPT_FALLBACK,
    );
    if (!Number.isFinite(raw) || raw < 0) return JOB_CREDIT_PER_ACCEPT_FALLBACK;
    return Math.floor(raw);
  }

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
   * How many pack credits this worker spent (and got back) for one booking.
   * Used on Booking Details — the booking entity itself does not store this.
   */
  async getBookingCreditUsage(
    userId: string,
    bookingId: string,
  ): Promise<{ creditsUsed: number; creditsRefunded: number }> {
    const txs = await this.creditTxRepo.find({
      where: { user: { id: userId }, bookingId },
    });
    let creditsUsed = 0;
    let creditsRefunded = 0;
    for (const t of txs) {
      if (t.reason === CreditTransactionReason.JOB_ACCEPTED) {
        creditsUsed += Math.abs(t.delta);
      } else if (
        t.reason === CreditTransactionReason.REFUND_CUSTOMER_CANCEL ||
        t.reason === CreditTransactionReason.REFUND_NOSHOW
      ) {
        creditsRefunded += Math.max(0, t.delta);
      }
    }
    return { creditsUsed, creditsRefunded };
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
    const cost = await this.getCreditsPerAccept();

    const execute = async (manager: any) => {
      if (cost === 0) {
        const credit = await manager.findOne(JobCredit, {
          where: { user: { id: userId } },
        });
        return credit?.balance ?? 0;
      }

      const credit = await manager.findOne(JobCredit, {
        where: { user: { id: userId } },
        lock: { mode: 'pessimistic_write' },
      });

      if (!credit || credit.balance < cost) {
        throw new BadRequestException(
          'No job credits left. Buy a pack to continue.',
        );
      }

      credit.balance -= cost;
      await manager.save(credit);

      await manager.save(
        manager.create(CreditTransaction, {
          user: { id: userId } as User,
          delta: -cost,
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

      // Refund what was actually consumed for this booking (survives admin
      // changing job_credit_per_accept after the accept).
      const acceptTxs = await manager.find(CreditTransaction, {
        where: {
          user: { id: userId },
          bookingId,
          reason: CreditTransactionReason.JOB_ACCEPTED,
        },
        order: { createdAt: 'DESC' },
        take: 1,
      });
      const acceptTx = acceptTxs[0];
      const amount =
        acceptTx != null
          ? Math.abs(acceptTx.delta)
          : await this.getCreditsPerAccept();
      if (amount === 0) return;

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

      credit.balance += amount;
      await manager.save(credit);

      await manager.save(
        manager.create(CreditTransaction, {
          user: { id: userId } as User,
          delta: amount,
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
