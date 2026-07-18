import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Address } from './address.entity';
import { User } from '../users/user.entity';

@Injectable()
export class AddressesService {
  constructor(
    @InjectRepository(Address)
    private readonly addrRepo: Repository<Address>,
  ) {}

  // Save a new address scoped to the user. `label` is optional.
  async add(
    userId: string,
    data: { line: string; label?: string },
  ): Promise<Address> {
    const addr = this.addrRepo.create({
      user: { id: userId } as User,
      line: data.line,
      label: data.label,
    });
    return this.addrRepo.save(addr);
  }

  async remove(userId: string, id: string): Promise<{ removed: boolean }> {
    const result = await this.addrRepo.delete({
      id,
      user: { id: userId },
    });
    return { removed: (result.affected ?? 0) > 0 };
  }

  async getMyAddresses(userId: string): Promise<Address[]> {
    return this.addrRepo.find({
      where: { user: { id: userId } },
      order: { createdAt: 'DESC' },
    });
  }
}
