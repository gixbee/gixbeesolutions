import { Injectable, UnauthorizedException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    private jwtService: JwtService,
    private redisService: RedisService,
    private configService: ConfigService,
  ) {}

  // ── OTP Request ────────────────────────────────────────────────────────────

  async requestOtp(
    phoneNumber: string,
  ): Promise<{ message: string; devOtp?: string }> {
    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    // Store OTP in Redis with 5-minute TTL
    await this.redisService.saveOtp(`otp:${phoneNumber}`, otp);

    // TODO: Replace with Twilio Verify or MSG91 in production
    // await this.twilioClient.verify.v2
    //   .services(process.env.TWILIO_VERIFY_SERVICE_SID)
    //   .verifications.create({ to: phoneNumber, channel: 'sms' });

    const isProduction = this.configService.get('NODE_ENV') === 'production';

    if (!isProduction) {
      // Only log and return devOtp in non-production environments
      console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
      return { message: 'OTP sent successfully', devOtp: otp };
    }

    return { message: 'OTP sent successfully' };
  }

  // ── OTP Verify ────────────────────────────────────────────────────────────

  async verifyOtp(
    phoneNumber: string,
    otp: string,
  ): Promise<{ accessToken: string }> {
    const storedOtp = await this.redisService.getOtp(`otp:${phoneNumber}`);

    if (!storedOtp || storedOtp !== otp) {
      throw new UnauthorizedException('Invalid or expired OTP');
    }

    // Delete OTP after single use — prevents replay attacks
    await this.redisService.deleteOtp(`otp:${phoneNumber}`);

    // Create user if first login
    let user = await this.usersRepository.findOne({ where: { phoneNumber } });
    if (!user) {
      user = this.usersRepository.create({
        phoneNumber,
        name: '',                   // collected in RegistrationScreen after OTP
        role: UserRole.CUSTOMER,    // default to CUSTOMER — workers register via /register-pro
        isVerified: true,
        walletBalance: 0,           // no free credits — prevents wallet exploit
      });
      await this.usersRepository.save(user);
    }

    const payload = {
      sub: user.id,
      phoneNumber: user.phoneNumber,
      role: user.role,
    };

    return { accessToken: await this.jwtService.signAsync(payload) };
  }

  // ── Profile ────────────────────────────────────────────────────────────────

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
      name: user.name ?? '',
      email: null,
      avatar: user.profileImageUrl ?? null,
      role: user.role,
      hasWorkerProfile: user.hasWorkerProfile ?? false,
      isAvailableForWork: user.isAvailableForWork ?? true,
    };
  }

  // ── FCM Token Registration ─────────────────────────────────────────────────

  /**
   * Called by Flutter via PATCH /auth/fcm-token after OTP login.
   * Stores the device's Firebase FCM token in DB + Redis.
   * NotificationsService uses this token to push job notifications to the device.
   */
  async updatePushToken(
    userId: string,
    token: string,
  ): Promise<{ message: string }> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    user.fcmToken = token;
    await this.usersRepository.save(user);

    // Cache in Redis for fast lookup by NotificationsService
    await this.redisService.cacheFcmToken(userId, token);

    return { message: 'Push token updated' };
  }

  // ── Admin Login ────────────────────────────────────────────────────────────

  /**
   * Super-admin panel login.
   * Credentials must come from environment variables — never hardcoded.
   */
  async adminLogin(
    username: string,
    password: string,
  ): Promise<{ accessToken: string }> {
    const adminUsername = this.configService.get<string>('ADMIN_USERNAME');
    const adminPassword = this.configService.get<string>('ADMIN_PASSWORD');

    if (!adminUsername || !adminPassword) {
      throw new UnauthorizedException(
        'Admin credentials not configured on server',
      );
    }

    if (username !== adminUsername || password !== adminPassword) {
      throw new UnauthorizedException('Invalid admin credentials');
    }

    const payload = {
      sub: 'admin-001',
      role: UserRole.ADMIN,
      phoneNumber: 'admin',
    };

    return { accessToken: await this.jwtService.signAsync(payload) };
  }
}
