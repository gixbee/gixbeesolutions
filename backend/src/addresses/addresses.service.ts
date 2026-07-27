import { Injectable, NotFoundException } from '@nestjs/common';
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

  // Save a new address scoped to the user. `label` is optional; lat/lng come
  // from a confirmed map pin (never geocoding) and are optional.
  async add(
    userId: string,
    data: { line: string; label?: string; lat?: number; lng?: number },
  ): Promise<Address> {
    const addr = this.addrRepo.create({
      user: { id: userId } as User,
      line: data.line,
      label: data.label,
      lat: data.lat,
      lng: data.lng,
    });
    return this.addrRepo.save(addr);
  }

  /**
   * Backfill confirmed pin coordinates onto an existing saved address (the
   * first time the user reuses a coord-less address in Instant Help and
   * confirms its pin). Scoped to the owner — you can't move someone else's
   * saved address.
   */
  async updateCoords(
    userId: string,
    id: string,
    lat: number,
    lng: number,
  ): Promise<Address> {
    const addr = await this.addrRepo.findOne({
      where: { id, user: { id: userId } },
    });
    if (!addr) throw new NotFoundException('Address not found');
    addr.lat = lat;
    addr.lng = lng;
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
