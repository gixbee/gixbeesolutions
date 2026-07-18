import { Injectable, UnauthorizedException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
import { AdminStaffService } from '../admin-staff/admin-staff.service';
import {
  AdminStaffRole,
  ADMIN_PORTAL_PAGES,
} from '../admin-staff/admin-staff.entity';
import * as crypto from 'crypto';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    private jwtService: JwtService,
    private redisService: RedisService,
    private configService: ConfigService,
    private adminStaffService: AdminStaffService,
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

    // SECURITY FIX: this used to return the OTP in the HTTP response whenever
    // NODE_ENV !== 'production' — and the committed .env sets
    // NODE_ENV=development, so ANY deploy that forgot to override it handed
    // out a full auth bypass to anyone who called /auth/request-otp.
    // Now it requires an EXPLICIT opt-in flag that no real deployment sets.
    const otpEchoEnabled =
      this.configService.get('ALLOW_OTP_ECHO') === 'true' &&
      this.configService.get('NODE_ENV') !== 'production';

    if (otpEchoEnabled) {
      console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
      return { message: 'OTP sent successfully', devOtp: otp };
    }

    // No SMS provider is wired yet (MSG91/Twilio TODO above). Log server-side
    // so local testing still works, but never return the code to the caller.
    if (this.configService.get('NODE_ENV') !== 'production') {
      console.log(`[DEV] OTP for ${phoneNumber}: ${otp}`);
    }

    return { message: 'OTP sent successfully' };
  }

  // ── OTP Verify ────────────────────────────────────────────────────────────

  async verifyOtp(
    phoneNumber: string,
    otp: string,
  ): Promise<{ accessToken: string; refreshToken: string }> {
    // AUDIT FIX: atomic GETDEL — closes the get-then-delete replay window
    // where two concurrent verifies could both read the same OTP.
    const storedOtp = await this.redisService.consumeOtp(`otp:${phoneNumber}`);

    if (!storedOtp || storedOtp !== otp) {
      throw new UnauthorizedException('Invalid or expired OTP');
    }

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
   * 1) DB staff users (role-based pages)
   * 2) Fallback: env ADMIN_USERNAME / ADMIN_PASSWORD → full SUPER_ADMIN
   */
  async adminLogin(
    username: string,
    password: string,
  ): Promise<{
    accessToken: string;
    staffRole: AdminStaffRole;
    pages: string[];
    displayName: string;
    username: string;
  }> {
    const user = username?.trim() ?? '';
    const pass = password ?? '';

    // 1) Portal staff account
    const staff = await this.adminStaffService.validateCredentials(user, pass);
    if (staff) {
      const pages = this.adminStaffService.effectivePages(staff);
      const payload = {
        sub: staff.id,
        role: UserRole.ADMIN,
        staffRole: staff.staffRole,
        pages,
        username: staff.username,
        displayName: staff.displayName || staff.username,
        phoneNumber: 'admin',
      };
      return {
        accessToken: await this.jwtService.signAsync(payload),
        staffRole: staff.staffRole,
        pages,
        displayName: payload.displayName,
        username: staff.username,
      };
    }

    // 2) Env bootstrap super-admin (legacy single credential)
    const adminUsername = this.configService.get<string>('ADMIN_USERNAME');
    const adminPassword = this.configService.get<string>('ADMIN_PASSWORD');

    if (!adminUsername || !adminPassword) {
      throw new UnauthorizedException(
        'Admin credentials not configured on server',
      );
    }

    if (user !== adminUsername || pass !== adminPassword) {
      throw new UnauthorizedException('Invalid admin credentials');
    }

    const pages = [...ADMIN_PORTAL_PAGES];
    const payload = {
      sub: 'env-admin',
      role: UserRole.ADMIN,
      staffRole: AdminStaffRole.SUPER_ADMIN,
      pages,
      username: adminUsername,
      displayName: 'SuperAdmin',
      phoneNumber: 'admin',
    };

    return {
      accessToken: await this.jwtService.signAsync(payload),
      staffRole: AdminStaffRole.SUPER_ADMIN,
      pages,
      displayName: 'SuperAdmin',
      username: adminUsername,
    };
  }
}
