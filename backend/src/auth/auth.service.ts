import { Injectable, UnauthorizedException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
// import { SupabaseService } from './supabase.service'; // Removed dependency

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    private jwtService: JwtService,
    private redisService: RedisService,
    private configService: ConfigService,
  ) {}

  async requestOtp(phoneNumber: string): Promise<{ message: string; devOtp?: string }> {
    // TODO: Replace with MSG91 or Firebase Auth SMS integration
    // Step 1: Generate a random 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    // Step 2: Store OTP in Redis with 5-minute TTL (key: otp:{phoneNumber})
    await this.redisService.saveOtp(`otp:${phoneNumber}`, otp);
    // Step 3: Send SMS via MSG91
    // await this.smsService.send(phoneNumber, `Your Gixbee OTP is ${otp}`);
    console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
    return { message: 'OTP sent successfully', devOtp: otp };
  }

  async verifyOtp(phoneNumber: string, otp: string): Promise<{ accessToken: string }> {
    // Fetch OTP from Redis and compare
    const storedOtp = await this.redisService.getOtp(`otp:${phoneNumber}`);
    if (!storedOtp || storedOtp !== otp) {
      // In dev environment, allow bypassing with a master OTP pattern if desired, but here we enforce it
      throw new UnauthorizedException('Invalid or expired OTP');
    }
    await this.redisService.deleteOtp(`otp:${phoneNumber}`);

    let user = await this.usersRepository.findOne({ where: { phoneNumber } });

    if (!user) {
      user = this.usersRepository.create({
        phoneNumber,
        name: `User ${phoneNumber.slice(-4)}`,
        role: UserRole.OPERATOR,
        isVerified: true,
        walletBalance: 100, // Give new users Rs. 100 starting balance
      });
      await this.usersRepository.save(user);
    }

    const payload = { sub: user.id, phoneNumber: user.phoneNumber, role: user.role };
    return {
      accessToken: await this.jwtService.signAsync(payload),
    };
  }

  async getProfile(userId: string): Promise<{
    id: string;
    phone: string;
    name: string;
    email: string | null;
    avatar: string | null;
    role: string;
    hasWorkerProfile: boolean;
    isAvailableForWork: boolean;
  }> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    return {
      id: user.id,
      phone: user.phoneNumber,
      name: user.name || `User ${user.phoneNumber.slice(-4)}`,
      email: null,
      avatar: user.profileImageUrl || null,
      role: user.role,
      hasWorkerProfile: user.hasWorkerProfile ?? false,
      isAvailableForWork: user.isAvailableForWork ?? true,
    };
  }

  async updatePushToken(userId: string, token: string): Promise<{ message: string }> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    user.fcmToken = token; // Reusing the field — stores OneSignal push subscription ID now
    await this.usersRepository.save(user);
    // SYNC WITH REDIS
    await this.redisService.cacheFcmToken(userId, token);
    return { message: 'Push token updated' };
  }

  async adminLogin(username: string, password: string): Promise<{ accessToken: string }> {
    // Scaffold explicitly for the Super Admin panel Web UI
    if (username !== 'admin' || password !== 'admin') {
      throw new UnauthorizedException('Invalid admin credentials');
    }

    // Usually, you'd mint the token against a real DB admin user ID.
    // For scaffolding, we provide a valid dummy sub that allows bypass, mapped to the ADMIN role.
    const payload = { sub: 'admin-scaffold-001', role: UserRole.ADMIN, phoneNumber: 'admin' };
    return {
      accessToken: await this.jwtService.signAsync(payload),
    };
  }
}
