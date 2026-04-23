import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from '../users/user.entity';
import { WalletTransaction, TransactionType } from './wallet-transaction.entity';

@Injectable()
export class WalletsService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    @InjectRepository(WalletTransaction)
    private transactionsRepository: Repository<WalletTransaction>,
  ) {}

  async getBalance(userId: string): Promise<number> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found');
    return Number(user.walletBalance);
  }

  async deductBookingFee(userId: string): Promise<void> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found');

    const fee = 12;
    if (user.walletBalance < fee) {
      throw new BadRequestException('Insufficient wallet balance');
    }

    user.walletBalance -= fee;
    await this.usersRepository.save(user);

    const transaction = this.transactionsRepository.create({
      user,
      amount: fee,
      type: TransactionType.DEBIT,
      description: 'Gixbee Service Fee (Booking)',
    });
    await this.transactionsRepository.save(transaction);
  }

  async addFunds(userId: string, amount: number): Promise<number> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new BadRequestException('User not found');

    user.walletBalance = Number(user.walletBalance) + amount;
    await this.usersRepository.save(user);

    const transaction = this.transactionsRepository.create({
      user,
      amount,
      type: TransactionType.CREDIT,
      description: 'Wallet Recharge',
    });
    await this.transactionsRepository.save(transaction);

    return user.walletBalance;
  }

  async getTransactions(userId: string): Promise<WalletTransaction[]> {
    return this.transactionsRepository.find({
      where: { user: { id: userId } },
      order: { timestamp: 'DESC' },
    });
  }
}
