import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, ILike } from 'typeorm';
import { User, UserRole, UserApprovalStatus } from './user.entity';
import { Booking } from '../bookings/booking.entity';
import { Favourite } from '../favourites/favourite.entity';
import { parsePagination } from '../common/pagination';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    @InjectRepository(Booking)
    private bookingsRepository: Repository<Booking>,
    @InjectRepository(Favourite)
    private favouritesRepository: Repository<Favourite>,
  ) {}

  async findById(id: string): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async getUserStats(userId: string): Promise<{
    bookingsCount: number;
    reviewsCount: number;
    savedCount: number;
  }> {
    try {
      const user = await this.usersRepository.findOne({
        where: { id: userId },
      });
      if (!user) {
        return { bookingsCount: 0, reviewsCount: 0, savedCount: 0 };
      }

      const bookingsCount = await this.bookingsRepository.count({
        where: { customer: { id: userId } },
      });

      // savedCount = how many workers this user has favourited. Sourced from the
      // real `favourites` table (Pass 104 module) so the Profile "SAVED" stat
      // reflects actual saves instead of the previous hardcoded 0.
      const savedCount = await this.favouritesRepository.count({
        where: { user: { id: userId } },
      });

      return {
        bookingsCount,
        reviewsCount: 0,
        savedCount,
      };
    } catch {
      // Handle invalid UUID format or any DB errors gracefully
      return { bookingsCount: 0, reviewsCount: 0, savedCount: 0 };
    }
  }

  async updateProfile(
    userId: string,
    data: Partial<User>,
    opts?: { allowPrivilegedFields?: boolean },
  ): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    if (data.name !== undefined) user.name = data.name;
    if (data.profileImageUrl !== undefined)
      user.profileImageUrl = data.profileImageUrl;
    if (data.isAvailableForWork !== undefined)
      user.isAvailableForWork = data.isAvailableForWork;
    if (opts?.allowPrivilegedFields) {
      if (data.role !== undefined) user.role = data.role;
      if (data.hasWorkerProfile !== undefined)
        user.hasWorkerProfile = data.hasWorkerProfile;
    }

    return this.usersRepository.save(user);
  }

  async updateFcmToken(userId: string, token: string): Promise<User> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    user.fcmToken = token;
    return this.usersRepository.save(user);
  }

  /**
   * Paginated admin user list. Nested talent relations amplify row size —
   * never load the whole table.
   */
  async findAll(page = 1, limit = 50): Promise<User[]> {
    const p = parsePagination(page, limit);
    return this.usersRepository.find({
      order: { createdAt: 'DESC' },
      relations: ['talentProfile', 'talentProfile.professionalSkills'],
      skip: p.skip,
      take: p.limit,
    });
  }

  /**
   * Name/phone lookup so an operator (or any admin picker) can be found by a
   * human-readable query instead of pasting a raw UUID into addOperator
   * (P106 operator-picker foundation). Case-insensitive partial match on name
   * OR phoneNumber. Returns a lean projection (no fcmToken/wallet/flags) and is
   * capped (1..50) so an empty or pathological query can't dump the whole table.
   * An empty/whitespace query short-circuits to [] with no DB hit.
   */
  async searchUsers(
    query: string,
    limit = 20,
    opts?: { includePhone?: boolean },
  ): Promise<
    Pick<User, 'id' | 'name' | 'phoneNumber' | 'role' | 'profileImageUrl'>[]
  > {
    const q = (query || '').trim();
    if (!q || q.length < 3) return [];
    const take = Math.min(Math.max(Math.trunc(limit) || 20, 1), 50);
    const rows = await this.usersRepository.find({
      where: [{ name: ILike(`%${q}%`) }, { phoneNumber: ILike(`%${q}%`) }],
      select: ['id', 'name', 'phoneNumber', 'role', 'profileImageUrl'],
      take,
      order: { name: 'ASC' },
    });
    if (opts?.includePhone) return rows;
    return rows.map(({ phoneNumber: _phone, ...rest }) => rest);
  }

  async updateApprovalStatus(
    id: string,
    status: UserApprovalStatus,
  ): Promise<User> {
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
    const totalWorkers = await this.usersRepository.count({
      where: { hasWorkerProfile: true },
    });
    const totalBookings = await this.bookingsRepository.count();
    const pendingApprovals = await this.usersRepository.count({
      where: { approvalStatus: UserApprovalStatus.PENDING },
    });

    // Recent users list
    const recentUsers = await this.usersRepository.find({
      order: { createdAt: 'DESC' },
      take: 5,
    });

    return {
      totalUsers,
      totalWorkers,
      totalBookings,
      pendingApprovals,
      recentUsers,
    };
  }
}
