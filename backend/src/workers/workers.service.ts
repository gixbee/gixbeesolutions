import { Injectable, NotFoundException, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { WorkerProfile } from './worker-profile.entity';
import { WalletsService } from '../wallets/wallets.service';
import { TalentProfile } from '../talent/talent-profile.entity';
import { ProfessionalSkill } from '../talent/professional-skill.entity';
import { User, UserApprovalStatus } from '../users/user.entity';
import { Booking, BookingStatus } from '../bookings/booking.entity';

// Worker data matching the Flutter Worker model's expectations exactly
export interface WorkerDto {
  id: string;
  name: string;
  title: string;
  bio: string;
  image_url: string;
  rating: number;
  completed_jobs: number;
  review_count: number;
  is_featured: boolean;
  hourly_rate: number;
  skills: string[];
  availability_tags: string[];
  primary_type: string;
  is_active?: boolean;
  status: 'available' | 'busy';
}

@Injectable()
export class WorkersService {
  constructor(
    @InjectRepository(WorkerProfile)
    private readonly workersRepository: Repository<WorkerProfile>,
    @InjectRepository(TalentProfile)
    private readonly talentRepository: Repository<TalentProfile>,
    @InjectRepository(ProfessionalSkill)
    private readonly skillRepository: Repository<ProfessionalSkill>,
    @InjectRepository(Booking)
    private readonly bookingsRepository: Repository<Booking>,
    private readonly walletsService: WalletsService,
  ) {}

  private async getWorkerStatus(userId: string): Promise<'available' | 'busy'> {
    const activeBooking = await this.bookingsRepository.findOne({
      where: [
        { operator: { id: userId }, status: BookingStatus.ACTIVE },
        { operator: { id: userId }, status: BookingStatus.ACCEPTED },
        { operator: { id: userId }, status: BookingStatus.CONFIRMED },
      ],
    });
    return activeBooking ? 'busy' : 'available';
  }

  /**
   * Helper mapper to convert from TypeORM entity to Flutter's DTO interface
   * This handles the shape mismatch from DB structure to API payload.
   */
  private  mapToDto(profile: WorkerProfile, status: 'available' | 'busy' = 'available'): WorkerDto {
    return {
      id: profile.user?.id || profile.id, // Using user ID externally if available
      name: profile.user?.name || 'Unknown Worker',
      title: profile.title || 'Professional Services',
      bio: profile.bio || '',
      image_url: profile.user?.profileImageUrl || 'https://i.pravatar.cc/150',
      rating: Number(profile.rating),
      completed_jobs: profile.completedJobs,
      review_count: profile.reviewCount,
      is_featured: false, // Could be logic driven
      hourly_rate: Number(profile.hourlyRate),
      skills: profile.skills || [],
      availability_tags: profile.availabilityTags || [],
      primary_type: 'manual', // Can be dynamically deduced based on skills
      is_active: profile.isActive,
      status: status,
    };
  }

  private mapTalentToDto(profile: TalentProfile, status: 'available' | 'busy' = 'available'): WorkerDto {
    const primarySkill = profile.professionalSkills?.[0];
    return {
      id: profile.user?.id || profile.id,
      name: profile.user?.name || 'Unknown Professional',
      title: primarySkill ? `${primarySkill.name} Expert` : 'Professional Services',
      bio: profile.experience || '',
      image_url: profile.user?.profileImageUrl || 'https://i.pravatar.cc/150',
      rating: 5.0, // Default for new pros
      completed_jobs: 0,
      review_count: 0,
      is_featured: false,
      hourly_rate: primarySkill ? Number(primarySkill.hourlyRate) : (profile.hourlyRate || 0),
      skills: profile.professionalSkills?.map(s => s.name) || [],
      availability_tags: [status === 'available' ? 'Available Now' : 'Currently Busy'],
      primary_type: 'manual',
      is_active: true, // Professionals are considered active if they have a profile for now
      status: status,
    };
  }

  async getAll(requesterId?: string): Promise<WorkerDto[]> {
    // 1. Fetch from WorkerProfile
    const profiles = await this.workersRepository.find({
      relations: ['user'],
    });
    
    // 2. Fetch from TalentProfile
    const talentProfiles = await this.talentRepository.find({
      relations: ['user', 'professionalSkills'],
    });

    const allWorkerDtos: WorkerDto[] = [];

    for (const p of profiles) {
      const userId = p.user?.id || p.id;
      if (requesterId && userId === requesterId) continue;
      
      // Skip if explicitly unavailable or not fully approved
      if (p.user?.isAvailableForWork === false) continue;
      if (p.user && p.user.approvalStatus !== UserApprovalStatus.APPROVED) continue;
      
      const status = await this.getWorkerStatus(userId);
      allWorkerDtos.push(this.mapToDto(p, status));
    }

    for (const p of talentProfiles) {
      const userId = p.user?.id || p.id;
      if (requesterId && userId === requesterId) continue;

      // Skip if explicitly unavailable or not fully approved
      if (p.user?.isAvailableForWork === false) continue;
      if (p.user && p.user.approvalStatus !== UserApprovalStatus.APPROVED) continue;

      const status = await this.getWorkerStatus(userId);
      allWorkerDtos.push(this.mapTalentToDto(p, status));
    }

    // 3. Deduplicate by user ID
    const uniqueWorkersMap = new Map<string, WorkerDto>();
    for (const w of allWorkerDtos) {
      if (!uniqueWorkersMap.has(w.id)) {
        uniqueWorkersMap.set(w.id, w);
      }
    }

    return Array.from(uniqueWorkersMap.values());
  }

  async getById(id: string): Promise<WorkerDto> {
    const profile = await this.workersRepository.findOne({
      where: { id },
      relations: ['user'],
    });

    if (!profile) {
      const userProfile = await this.workersRepository.findOne({
        where: { user: { id } },
        relations: ['user'],
      });
      if (!userProfile) {
        throw new NotFoundException(`Worker with ID ${id} not found`);
      }
      const status = await this.getWorkerStatus(userProfile.user?.id || userProfile.id);
      return this.mapToDto(userProfile, status);
    }

    const status = await this.getWorkerStatus(profile.user?.id || profile.id);
    return this.mapToDto(profile, status);
  }

  // ─────────────────────────────────────────────
  // GO-LIVE TOGGLE (RATE LIMITED TO 2/DAY)
  // ─────────────────────────────────────────────

  async toggleGoLive(id: string): Promise<{ isActive: boolean; message: string }> {
    // We assume the ID passed is the internal profile ID or the user ID
    let profile = await this.workersRepository.findOne({ where: { id }, relations: ['user'] });
    
    if (!profile) {
      profile = await this.workersRepository.findOne({ where: { user: { id } }, relations: ['user'] });
    }

    if (!profile) {
      throw new NotFoundException('Worker profile not found');
    }

    const todayDateStr = new Date().toISOString().split('T')[0]; // YYYY-MM-DD

    // Reset rate limits if it's a new day
    if (profile.goLiveToggleDate !== todayDateStr) {
      profile.goLiveToggleDate = todayDateStr;
      profile.goLiveToggleCountToday = 0;
    }

    // Only check balance when going LIVE, not when going offline
    if (!profile.isActive) {
      if (profile.isFirstJobDone) {
        const balance = await this.walletsService.getBalance(profile.user?.id || id);
        if (balance < 12) {
          throw new BadRequestException(
            'Minimum Rs.12 wallet balance required to go live. Please top up.'
          );
        }
      }
    }

    // Rate Limit enforcement: Max 2 toggles per day (to prevent spamming proximity map)
    if (profile.goLiveToggleCountToday >= 2) {
      throw new BadRequestException('You have reached the limit of 2 Go-Live toggles for today. Try again tomorrow.');
    }

    // Process toggle
    profile.isActive = !profile.isActive;
    profile.goLiveToggleCountToday += 1;

    await this.workersRepository.save(profile);

    return {
      isActive: profile.isActive,
      message: profile.isActive 
        ? 'You are now LIVE on the map and accepting jobs.' 
        : 'You are now OFFLINE. Customers cannot dispatch you instantly.',
    };
  }

  async addStrike(userId: string): Promise<void> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) return;
    
    profile.strikeCount = (profile.strikeCount || 0) + 1;
    if (profile.strikeCount >= 3) {
      profile.isActive = false;
      // Note: we can optionally set verificationStatus to SUSPENDED here if available
    }
    await this.workersRepository.save(profile);
  }

  // DEFECT-006: Create new worker profile
  async createProfile(userId: string, data: {
    skills: string[];
    hourlyRate: number;
    bio?: string;
    title?: string;
  }): Promise<WorkerProfile> {
    const existing = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (existing) {
      throw new BadRequestException('Worker profile already exists');
    }
    const profile = this.workersRepository.create({
      user: { id: userId } as any,
      skills: data.skills,
      hourlyRate: data.hourlyRate,
      bio: data.bio,
      title: data.title,
      isActive: false,
      isFirstJobDone: false,
      verificationStatus: 'PENDING' as any,
    });
    return this.workersRepository.save(profile);
  }

  // DEFECT-007: Update hourly rate with 2/day rate limit
  async updateHourlyRate(userId: string, newRate: number): Promise<{ hourlyRate: number }> {
    const profile = await this.workersRepository.findOne({
      where: { user: { id: userId } },
    });
    if (!profile) throw new NotFoundException('Worker profile not found');

    const todayStr = new Date().toISOString().split('T')[0];
    if (profile.rateUpdateDate !== todayStr) {
      profile.rateUpdateDate = todayStr;
      profile.rateUpdateCountToday = 0;
    }
    if (profile.rateUpdateCountToday >= 2) {
      throw new BadRequestException('Hourly rate can only be updated twice per day.');
    }
    profile.hourlyRate = newRate;
    profile.rateUpdateCountToday += 1;
    await this.workersRepository.save(profile);
    return { hourlyRate: newRate };
  }

  // DEFECT-008: Nearby workers filtered by skill
  async getNearby(requesterId: string, skill: string, lat: number, lng: number): Promise<WorkerDto[]> {
    const all = await this.workersRepository.find({
      where: { isActive: true },
      relations: ['user'],
    });
    
    const filtered = all.filter(w => {
      const isSelf = (w.user?.id === requesterId) || (w.id === requesterId);
      const isUnavailable = w.user?.isAvailableForWork === false;
      const isNotApproved = w.user && w.user.approvalStatus !== UserApprovalStatus.APPROVED;
      const hasSkill = w.skills?.some(s => s.toLowerCase().includes(skill.toLowerCase()));

      return !isSelf && !isUnavailable && !isNotApproved && hasSkill;
    });

    const result: WorkerDto[] = [];
    for (const w of filtered) {
      const status = await this.getWorkerStatus(w.user?.id || w.id);
      result.push(this.mapToDto(w, status));
    }
    return result;
    // Production: use PostGIS ST_DWithin for real geo-radius filtering
  }
}
