import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MasterEntry, MasterEntryType } from './master-entry.entity';

@Injectable()
export class MasterEntriesService {
  constructor(
    @InjectRepository(MasterEntry)
    private readonly masterEntryRepo: Repository<MasterEntry>,
  ) {}

  async create(data: Partial<MasterEntry>): Promise<MasterEntry> {
    const entry = this.masterEntryRepo.create(data);
    return this.masterEntryRepo.save(entry);
  }

  async findAll(type?: MasterEntryType, isActive?: boolean): Promise<MasterEntry[]> {
    const where: any = {};
    if (type) where.type = type;
    if (isActive !== undefined) where.isActive = isActive;
    
    return this.masterEntryRepo.find({ where, order: { createdAt: 'DESC' } });
  }

  async findOne(id: string): Promise<MasterEntry> {
    const entry = await this.masterEntryRepo.findOne({ where: { id } });
    if (!entry) throw new NotFoundException('Master entry not found');
    return entry;
  }

  async update(id: string, data: Partial<MasterEntry>): Promise<MasterEntry> {
    const entry = await this.findOne(id);
    Object.assign(entry, data);
    return this.masterEntryRepo.save(entry);
  }

  async remove(id: string): Promise<void> {
    const entry = await this.findOne(id);
    await this.masterEntryRepo.remove(entry);
  }
}
