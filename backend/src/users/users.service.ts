import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole, UserApprovalStatus } from './user.entity';
import { Booking } from '../bookings/booking.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
  ) {}

  async findById(id: string): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async getUserStats(userId: string): Promise<{ bookingsCount: number; reviewsCount: number; savedCount: number }> {
    try {
      const user = await this.usersRepository.findOne({ where: { id: userId } });
      if (!user) {
        return { bookingsCount: 0, reviewsCount: 0, savedCount: 0 };
      }

      const bookingsCount = await this.bookingsRepository.count({
        where: { customer: { id: userId } },
      });

      return {
        bookingsCount,
        reviewsCount: 0,
        savedCount: 0,
      };
    } catch {
      // Handle invalid UUID format or any DB errors gracefully
      return { bookingsCount: 0, reviewsCount: 0, savedCount: 0 };
    }
  }

  async updateProfile(userId: string, data: Partial<User>): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    if (data.name !== undefined) user.name = data.name;
    if (data.profileImageUrl !== undefined) user.profileImageUrl = data.profileImageUrl;
    if (data.isAvailableForWork !== undefined) user.isAvailableForWork = data.isAvailableForWork;

    return this.usersRepository.save(user);
  }

  async updateFcmToken(userId: string, token: string): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    user.fcmToken = token;
    return this.usersRepository.save(user);
  }

  async findAll(): Promise<User[]> {
    return this.usersRepository.find({
      order: { createdAt: 'DESC' },
      relations: ['talentProfile', 'talentProfile.professionalSkills'],
    });
  }

  async updateApprovalStatus(id: string, status: UserApprovalStatus): Promise<User> {
    const user = await this.findById(id);
    user.approvalStatus = status;
    
    // Auto-verify if approved
    if (status === UserApprovalStatus.APPROVED) {
      user.isVerified = true;
      user.hasWorkerProfile = true;
    } else if (status === UserApprovalStatus.REJECTED) {
      user.isVerified = false;
    }
    
    return this.usersRepository.save(user);
  }

  async updateVerification(id: string, isVerified: boolean): Promise<User> {
    const user = await this.findById(id);
    user.isVerified = isVerified;
    if (isVerified) {
       user.hasWorkerProfile = true; // Auto-enable worker features on verification
    }
    return this.usersRepository.save(user);
  }

  async getSystemSummary(): Promise<any> {
    const totalUsers = await this.usersRepository.count();
    const totalWorkers = await this.usersRepository.count({ where: { hasWorkerProfile: true } });
    const totalBookings = await this.bookingsRepository.count();
    const pendingApprovals = await this.usersRepository.count({ where: { approvalStatus: UserApprovalStatus.PENDING } });

    // Recent users list
    const recentUsers = await this.usersRepository.find({
      order: { createdAt: 'DESC' },
      take: 5
    });

    return {
      totalUsers,
      totalWorkers,
      totalBookings,
      pendingApprovals,
      recentUsers
    };
  }
}
