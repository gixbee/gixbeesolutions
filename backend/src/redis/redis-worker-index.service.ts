import { forwardRef, Inject, Injectable } from '@nestjs/common';
import { RedisService } from './redis.service';

export interface LocationCache {
  lat: number;
  lng: number;
  timestamp: string;
}

@Injectable()
export class RedisWorkerIndexService {
  private static readonly WORKER_SNAPSHOT = 'worker:snapshot:';
  private static readonly SKILL_INDEX = 'skill:index:';

  constructor(
    @Inject(forwardRef(() => RedisService))
    private readonly redis: RedisService,
  ) {}

  async updateWorkerLocation(
    workerId: string,
    lat: number,
    lng: number,
  ): Promise<void> {
    const payload: LocationCache = {
      lat,
      lng,
      timestamp: new Date().toISOString(),
    };
    await this.redis.set(
      `worker:location:${workerId}`,
      JSON.stringify(payload),
      60 * 60,
    );
    await this.updateWorkerGeoLocation(workerId, lat, lng);
  }

  async getWorkerLocation(workerId: string): Promise<LocationCache | null> {
    const data = await this.redis.get(`worker:location:${workerId}`);
    try {
      return data ? (JSON.parse(data) as LocationCache) : null;
    } catch {
      return null;
    }
  }

  async updateWorkerGeoLocation(
    workerId: string,
    lat: number,
    lng: number,
  ): Promise<void> {
    await this.redis.geoAdd(workerId, lat, lng);
  }

  async removeWorkerFromGeoIndex(workerId: string): Promise<void> {
    await this.redis.geoRem(workerId);
  }

  async searchNearbyWorkerIds(
    lat: number,
    lng: number,
    radiusKm: number,
  ): Promise<string[] | null> {
    return this.redis.geoSearch(lat, lng, radiusKm);
  }

  async cacheWorkerSnapshot(workerId: string, snapshot: any): Promise<void> {
    await this.redis.set(
      `${RedisWorkerIndexService.WORKER_SNAPSHOT}${workerId}`,
      JSON.stringify(snapshot),
      24 * 60 * 60,
    );
  }

  async getWorkerSnapshot(workerId: string): Promise<any | null> {
    const data = await this.redis.get(
      `${RedisWorkerIndexService.WORKER_SNAPSHOT}${workerId}`,
    );
    try {
      return data ? JSON.parse(data) : null;
    } catch {
      return null;
    }
  }

  async indexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    for (const skill of skills) {
      await this.redis.sAdd(this.skillKey(skill), workerId, 24 * 60 * 60);
    }
  }

  async unindexWorkerSkills(workerId: string, skills: string[]): Promise<void> {
    for (const skill of skills) {
      await this.redis.sRem(this.skillKey(skill), workerId);
    }
  }

  async getWorkerIdsBySkill(skill: string): Promise<string[]> {
    return this.redis.sMembers(this.skillKey(skill));
  }

  private skillKey(skill: string): string {
    return `${RedisWorkerIndexService.SKILL_INDEX}${skill.toLowerCase().trim()}`;
  }
}
