import { Injectable, NotFoundException, OnModuleInit } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { City } from './city.entity';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class CitiesService implements OnModuleInit {
  private readonly CACHE_KEY_PREFIX = 'cities';

  constructor(
    @InjectRepository(City)
    private readonly cityRepo: Repository<City>,
    private readonly redisService: RedisService,
  ) {}

  async onModuleInit() {
    // Seed the launch cities once (the list the app previously hardcoded in
    // home_location_picker_screen.dart). After this, cities are managed
    // exclusively from the super-admin portal.
    const count = await this.cityRepo.count();
    if (count === 0) {
      const seed: Array<Partial<City>> = [
        { name: 'Kochi', state: 'Kerala', lat: 9.9312, lng: 76.2673 },
        { name: 'Thiruvananthapuram', state: 'Kerala', lat: 8.5241, lng: 76.9366 },
        { name: 'Kozhikode', state: 'Kerala', lat: 11.2588, lng: 75.7804 },
        { name: 'Bangalore', state: 'Karnataka', lat: 12.9716, lng: 77.5946 },
        { name: 'Chennai', state: 'Tamil Nadu', lat: 13.0827, lng: 80.2707 },
        { name: 'Mumbai', state: 'Maharashtra', lat: 19.076, lng: 72.8777 },
        { name: 'Coimbatore', state: 'Tamil Nadu', lat: 11.0168, lng: 76.9558 },
      ];
      await this.cityRepo.save(seed.map((c) => this.cityRepo.create({ ...c, isActive: true })));
      console.log('Seeded default serviceable cities');
    }
  }

  private async clearCache(): Promise<void> {
    const keys = await this.redisService.keys(`${this.CACHE_KEY_PREFIX}:*`);
    if (keys.length > 0) {
      await this.redisService.del(...keys);
    }
  }

  async create(data: Partial<City>): Promise<City> {
    const city = this.cityRepo.create(data);
    const result = await this.cityRepo.save(city);
    await this.clearCache();
    return result;
  }

  async findAll(isActive?: boolean): Promise<City[]> {
    const cacheKey = `${this.CACHE_KEY_PREFIX}:${isActive ?? 'any'}`;
    const cached = await this.redisService.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }

    const where: any = {};
    if (isActive !== undefined) where.isActive = isActive;
    const cities = await this.cityRepo.find({ where, order: { state: 'ASC', name: 'ASC' } });

    // Cities change rarely — cache for 1 hour, invalidated on any write.
    await this.redisService.set(cacheKey, JSON.stringify(cities), 3600);
    return cities;
  }

  async findOne(id: string): Promise<City> {
    const city = await this.cityRepo.findOne({ where: { id } });
    if (!city) throw new NotFoundException('City not found');
    return city;
  }

  async update(id: string, data: Partial<City>): Promise<City> {
    const city = await this.findOne(id);
    Object.assign(city, data);
    const result = await this.cityRepo.save(city);
    await this.clearCache();
    return result;
  }

  async remove(id: string): Promise<void> {
    const city = await this.findOne(id);
    await this.cityRepo.remove(city);
    await this.clearCache();
  }
}
