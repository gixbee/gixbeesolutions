import { Injectable, UnauthorizedException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
import * as crypto from 'crypto';

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
  ): Promise<{ accessToken: string; refreshToken: string }> {
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

    return this.generateTokenPair(user);
  }

  // ── Token Pair Generation ──────────────────────────────────────────────────

  private async generateTokenPair(user: User): Promise<{ accessToken: string; refreshToken: string }> {
    const payload = {
      sub: user.id,
      phoneNumber: user.phoneNumber,
      role: user.role,
    };

    // Access token: short-lived (1h, configured in auth.module.ts)
    const accessToken = await this.jwtService.signAsync(payload);

    // Refresh token: long-lived (30d), signed with a different secret suffix
    const refreshSecret = (this.configService.get<string>('JWT_SECRET') ?? 'fallback-secret') + '-refresh';
    const refreshToken = await this.jwtService.signAsync(
      { sub: user.id, type: 'refresh' },
      { secret: refreshSecret, expiresIn: '30d' },
    );

    // Store refresh token hash in Redis (30-day TTL)
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    await this.redisService.set(`refresh:${user.id}`, tokenHash, 30 * 24 * 60 * 60);

    return { accessToken, refreshToken };
  }

  // ── Refresh Access Token ──────────────────────────────────────────────────

  async refreshAccessToken(refreshToken: string): Promise<{ accessToken: string }> {
    const refreshSecret = (this.configService.get<string>('JWT_SECRET') ?? 'fallback-secret') + '-refresh';

    let payload: any;
    try {
      payload = await this.jwtService.verifyAsync(refreshToken, { secret: refreshSecret });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    if (payload.type !== 'refresh') {
      throw new UnauthorizedException('Invalid token type');
    }

    // Verify the token hash matches what's stored in Redis
    const tokenHash = crypto.createHash('sha256').update(refreshToken).digest('hex');
    const storedHash = await this.redisService.get(`refresh:${payload.sub}`);

    if (!storedHash || storedHash !== tokenHash) {
      throw new UnauthorizedException('Refresh token revoked or expired');
    }

    // Issue new access token
    const user = await this.usersRepository.findOne({ where: { id: payload.sub } });
    if (!user) throw new UnauthorizedException('User not found');

    const accessPayload = {
      sub: user.id,
      phoneNumber: user.phoneNumber,
      role: user.role,
    };

    const accessToken = await this.jwtService.signAsync(accessPayload);
    return { accessToken };
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
