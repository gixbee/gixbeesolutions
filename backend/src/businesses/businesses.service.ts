import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Business } from './business.entity';
import { User } from '../users/user.entity';

@Injectable()
export class BusinessesService {
  constructor(
    @InjectRepository(Business)
    private readonly businessRepo: Repository<Business>,
  ) {}

  async create(ownerId: string, data: Partial<Business>): Promise<Business> {
    const business = this.businessRepo.create({
      ...data,
      owner: { id: ownerId } as User,
      status: 'PENDING',
    });
    return this.businessRepo.save(business);
  }

  async getMyBusinesses(ownerId: string): Promise<Business[]> {
    return this.businessRepo.find({
      where: { owner: { id: ownerId } },
      order: { createdAt: 'DESC' },
    });
  }

  async getById(id: string): Promise<Business> {
    const business = await this.businessRepo.findOne({ where: { id }, relations: ['owner'] });
    if (!business) throw new NotFoundException('Business not found');
    return business;
  }

  async addOperator(businessId: string, userId: string): Promise<Business> {
    const business = await this.getById(businessId);
    const ops = business.operatorIds || [];
    if (!ops.includes(userId)) {
      ops.push(userId);
      business.operatorIds = ops;
      return this.businessRepo.save(business);
    }
    return business;
  }

  async addOfflineDay(businessId: string, dateIsoString: string): Promise<Business> {
    const business = await this.getById(businessId);
    const days = business.offlineDays || [];
    if (!days.includes(dateIsoString)) {
      days.push(dateIsoString);
      business.offlineDays = days;
      return this.businessRepo.save(business);
    }
    return business;
  }
}
