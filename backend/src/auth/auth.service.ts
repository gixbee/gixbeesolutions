import { Injectable, UnauthorizedException, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User, UserRole } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';
import { SupabaseService } from './supabase.service';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private usersRepository: Repository<User>,
    private jwtService: JwtService,
    private redisService: RedisService,
    private configService: ConfigService,
    private supabaseService: SupabaseService,
  ) {}

  async loginWithSupabase(idToken: string): Promise<{ accessToken: string }> {
    try {
      let phoneNumber: string | undefined;

      // --- DEV BYPASS START ---
      const isDev = this.configService.get('NODE_ENV') === 'development';

      if (isDev) {
        if (idToken === 'mock-token-bypass') {
          // Pure mock bypass for local dev
          phoneNumber = '+919605956941';
          console.warn('[AUTH] [DEV BYPASS] Authenticated using mock token');
        } else {
          // Decode real frontend token payload without network verification
          const encodedPayload = idToken.split('.')[1];
          if (encodedPayload) {
            const decoded = JSON.parse(Buffer.from(encodedPayload, 'base64').toString());
            // Supabase puts phone in user_metadata or phone if confirmed
            phoneNumber = decoded.phone || decoded.phone_number || '+919605956941';
          } else {
            phoneNumber = '+919605956941';
          }
          console.warn(`[AUTH] [DEV BYPASS] Decoded token for ${phoneNumber}`);
        }
      } else {
        // 1. Verify the ID Token with Supabase
        const supabaseUser = await this.supabaseService.verifyToken(idToken);
        phoneNumber = supabaseUser.phone;
      }

      if (!phoneNumber) {
        throw new UnauthorizedException('Supabase user does not have a phone number');
      }

      // 2. Find or create the user based on the phone number
      let user = await this.usersRepository.findOne({ where: { phoneNumber } });

      // Legacy fallback: old records stored without country code (e.g. "9605956941")
      // Firebase returns "+919605956941", so try matching the last 10 digits
      if (!user && phoneNumber.length > 10) {
        const last10 = phoneNumber.slice(-10);
        user = await this.usersRepository.findOne({ where: { phoneNumber: last10 } });
        if (user) {
          // Migrate the stored number to the international format
          console.log(`[AUTH] Migrating legacy phone ${user.phoneNumber} → ${phoneNumber}`);
          user.phoneNumber = phoneNumber;
          await this.usersRepository.save(user);
        }
      }

      if (!user) {
        user = this.usersRepository.create({
          phoneNumber,
          name: `User ${phoneNumber.slice(-4)}`,
          role: UserRole.OPERATOR,
          isVerified: true,
          walletBalance: 100, // Starting balance for new users
        });
        await this.usersRepository.save(user);
      }

      // 3. Issue Gixbee JWT
      const payload = { sub: user.id, phoneNumber: user.phoneNumber, role: user.role };
      return {
        accessToken: await this.jwtService.signAsync(payload),
      };
    } catch (error) {
      console.error('Firebase Auth Error:', error);
      throw new UnauthorizedException('Invalid Firebase Token');
    }
  }

  async requestOtp(phoneNumber: string): Promise<{ message: string }> {
    // TODO: Replace with MSG91 or Firebase Auth SMS integration
    // Step 1: Generate a random 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    // Step 2: Store OTP in Redis with 5-minute TTL (key: otp:{phoneNumber})
    await this.redisService.saveOtp(`otp:${phoneNumber}`, otp);
    // Step 3: Send SMS via MSG91
    // await this.smsService.send(phoneNumber, `Your Gixbee OTP is ${otp}`);
    console.log(`[DEV ONLY] OTP for ${phoneNumber}: ${otp}`);
    return { message: 'OTP sent successfully' };
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

  async getProfile(userId: string): Promise<{ id: string; phone: string; name: string; email: string | null; avatar: string | null }> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    return {
      id: user.id,
      phone: user.phoneNumber,
      name: user.name || `User ${user.phoneNumber.slice(-4)}`,
      email: null,
      avatar: user.profileImageUrl || null,
    };
  }

  async updatePushToken(userId: string, token: string): Promise<{ message: string }> {
    const user = await this.usersRepository.findOne({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');
    user.fcmToken = token; // Reusing the field — stores OneSignal push subscription ID now
    await this.usersRepository.save(user);
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
