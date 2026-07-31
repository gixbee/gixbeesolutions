import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Favourite } from './favourite.entity';
import { User } from '../users/user.entity';

@Injectable()
export class FavouritesService {
  constructor(
    @InjectRepository(Favourite)
    private readonly favRepo: Repository<Favourite>,
  ) {}

  // Idempotent: adding a worker that's already favourited returns the existing
  // row instead of throwing or creating a duplicate.
  async add(userId: string, workerId: string): Promise<Favourite> {
    const existing = await this.favRepo.findOne({
      where: { user: { id: userId }, workerId },
    });
    if (existing) return existing;
    const fav = this.favRepo.create({
      user: { id: userId } as User,
      workerId,
    });
    return this.favRepo.save(fav);
  }

  async remove(
    userId: string,
    workerId: string,
  ): Promise<{ removed: boolean }> {
    const result = await this.favRepo.delete({
      user: { id: userId },
      workerId,
    });
    return { removed: (result.affected ?? 0) > 0 };
  }

  async isFavourite(
    userId: string,
    workerId: string,
  ): Promise<{ favourited: boolean }> {
    const count = await this.favRepo.count({
      where: { user: { id: userId }, workerId },
    });
    return { favourited: count > 0 };
  }

  async getMyFavourites(userId: string): Promise<Favourite[]> {
    return this.favRepo.find({
      where: { user: { id: userId } },
      order: { createdAt: 'DESC' },
    });
  }
}
