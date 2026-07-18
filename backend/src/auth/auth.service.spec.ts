import { UnauthorizedException, NotFoundException } from '@nestjs/common';
import * as crypto from 'crypto';
import { AuthService } from './auth.service';
import { UserRole } from '../users/user.entity';

/**
 * Unit tests for AuthService (OTP login + JWT lifecycle).
 *
 * Covered branches:
 * - requestOtp: stores a 6-digit OTP in Redis; returns devOtp ONLY in
 *   non-production (NODE_ENV !== 'production') and hides it in production.
 * - verifyOtp: rejects when no stored OTP / mismatch; on success consumes the
 *   OTP via atomic GETDEL (replay guard), creates a default-CUSTOMER user on
 *   first login (zero wallet, isVerified), reuses an existing user, and
 *   returns a token pair.
 * - generateTokenPair (via verifyOtp): signs access token with the default
 *   secret + a refresh token with the '<JWT_SECRET>-refresh' secret, and
 *   stores the sha256 hash of the refresh token in Redis with a 30-day TTL.
 * - refreshAccessToken: rejects an unverifiable token, a wrong token type, a
 *   revoked/absent hash, and a missing user; mints a fresh access token on the
 *   happy path.
 * - getProfile: maps the user entity to the API shape, applies null/empty
 *   defaults, throws NotFound when absent.
 * - updatePushToken: persists the FCM token on the user + caches it in Redis;
 *   throws NotFound when the user is absent.
 * - adminLogin: throws when credentials are not configured, when they do not
 *   match, and signs an ADMIN token on a match.
 *
 * All collaborators (User repo, JwtService, RedisService, ConfigService) are
 * mocked in-memory — no DB, no Redis, no real signing. `crypto` is real so the
 * hash-match assertions exercise the production code path.
 */

function makeDeps(opts: { user?: any; config?: Record<string, any> } = {}) {
  const saved: any[] = [];
  const redisStore = new Map<string, string>();

  const usersRepository: any = {
    findOne: jest.fn(async () => opts.user ?? null),
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (u: any) => {
      if (!u.id) u.id = 'new-user-id';
      saved.push(u);
      return u;
    }),
  };

  const jwtService: any = {
    // Echo back a deterministic token that encodes the payload + options so
    // assertions can distinguish access vs refresh tokens.
    signAsync: jest.fn(async (payload: any, options?: any) => {
      const tag = options?.secret ? `refresh(${options.secret})` : 'access';
      return `${tag}:${JSON.stringify(payload)}`;
    }),
    verifyAsync: jest.fn(),
  };

  const redisService: any = {
    saveOtp: jest.fn(async (key: string, otp: string) => {
      redisStore.set(key, otp);
    }),
    getOtp: jest.fn(async (key: string) => redisStore.get(key) ?? null),
    consumeOtp: jest.fn(async (key: string) => {
      const value = redisStore.get(key) ?? null;
      if (value !== null) redisStore.delete(key);
      return value;
    }),
    deleteOtp: jest.fn(async (key: string) => {
      redisStore.delete(key);
    }),
    set: jest.fn(async (key: string, value: string) => {
      redisStore.set(key, value);
    }),
    get: jest.fn(async (key: string) => redisStore.get(key) ?? null),
    cacheFcmToken: jest.fn(async (userId: string, token: string) => {
      redisStore.set(`fcm:${userId}`, token);
    }),
  };

  const config = opts.config ?? {};
  const configService: any = {
    get: jest.fn((key: string) => config[key]),
  };

  const adminStaffService: any = {
    validateCredentials: jest.fn(async () => null),
    effectivePages: jest.fn(() => []),
  };

  const service = new AuthService(
    usersRepository,
    jwtService,
    redisService,
    configService,
    adminStaffService,
  );

  return {
    service,
    usersRepository,
    jwtService,
    redisService,
    configService,
    adminStaffService,
    saved,
    redisStore,
  };
}

describe('AuthService.requestOtp', () => {
  it('stores a 6-digit OTP in Redis and returns devOtp in non-production', async () => {
    const { service, redisService } = makeDeps({
      config: { NODE_ENV: 'development', ALLOW_OTP_ECHO: 'true' },
    });

    const result = await service.requestOtp('+919000000001');

    expect(redisService.saveOtp).toHaveBeenCalledTimes(1);
    const [key, otp] = redisService.saveOtp.mock.calls[0];
    expect(key).toBe('otp:+919000000001');
    expect(otp).toMatch(/^\d{6}$/);
    // devOtp echoes the stored OTP so the dev client can auto-fill.
    expect(result.devOtp).toBe(otp);
    expect(result.message).toBe('OTP sent successfully');
  });

  it('hides devOtp in production', async () => {
    const { service, redisService } = makeDeps({ config: { NODE_ENV: 'production' } });

    const result = await service.requestOtp('+919000000002');

    expect(redisService.saveOtp).toHaveBeenCalledTimes(1);
    expect(result.devOtp).toBeUndefined();
    expect(result.message).toBe('OTP sent successfully');
  });
});

describe('AuthService.verifyOtp', () => {
  it('throws Unauthorized when no OTP is stored', async () => {
    const { service } = makeDeps();
    await expect(service.verifyOtp('+919000000003', '123456')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('throws Unauthorized when the OTP does not match (and still consumes it)', async () => {
    const { service, redisStore } = makeDeps();
    redisStore.set('otp:+919000000004', '111111');
    await expect(service.verifyOtp('+919000000004', '222222')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(redisStore.has('otp:+919000000004')).toBe(false);
  });

  it('creates a default-CUSTOMER user on first login and returns a token pair', async () => {
    const { service, usersRepository, redisService, saved, redisStore } = makeDeps({
      config: { JWT_SECRET: 'unit-secret' },
    });
    redisStore.set('otp:+919000000005', '654321');

    const result = await service.verifyOtp('+919000000005', '654321');

    // OTP consumed atomically (replay guard).
    expect(redisService.consumeOtp).toHaveBeenCalledWith('otp:+919000000005');
    expect(redisStore.has('otp:+919000000005')).toBe(false);
    expect(usersRepository.create).toHaveBeenCalledWith(
      expect.objectContaining({
        phoneNumber: '+919000000005',
        role: UserRole.CUSTOMER,
        isVerified: true,
        walletBalance: 0,
      }),
    );
    expect(saved).toHaveLength(1);
    expect(result.accessToken).toContain('access');
    expect(result.refreshToken).toContain('refresh(unit-secret-refresh)');
  });

  it('reuses an existing user without creating a new one', async () => {
    const existing = { id: 'u-existing', phoneNumber: '+919000000006', role: UserRole.OPERATOR };
    const { service, usersRepository, saved, redisStore } = makeDeps({
      user: existing,
      config: { JWT_SECRET: 'unit-secret' },
    });
    redisStore.set('otp:+919000000006', '777777');

    await service.verifyOtp('+919000000006', '777777');

    expect(usersRepository.create).not.toHaveBeenCalled();
    expect(saved).toHaveLength(0);
  });

  it('stores the sha256 hash of the refresh token in Redis with a 30-day TTL', async () => {
    const existing = { id: 'u-hash', phoneNumber: '+919000000007', role: UserRole.CUSTOMER };
    const { service, redisService, redisStore } = makeDeps({
      user: existing,
      config: { JWT_SECRET: 'unit-secret' },
    });
    redisStore.set('otp:+919000000007', '888888');

    const result = await service.verifyOtp('+919000000007', '888888');

    const expectedHash = crypto
      .createHash('sha256')
      .update(result.refreshToken)
      .digest('hex');
    expect(redisService.set).toHaveBeenCalledWith(
      'refresh:u-hash',
      expectedHash,
      30 * 24 * 60 * 60,
    );
  });
});

describe('AuthService.refreshAccessToken', () => {
  it('throws Unauthorized when the refresh token cannot be verified', async () => {
    const { service, jwtService } = makeDeps({ config: { JWT_SECRET: 'unit-secret' } });
    jwtService.verifyAsync.mockRejectedValueOnce(new Error('bad sig'));

    await expect(service.refreshAccessToken('garbage')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('throws Unauthorized when the token type is not "refresh"', async () => {
    const { service, jwtService } = makeDeps({ config: { JWT_SECRET: 'unit-secret' } });
    jwtService.verifyAsync.mockResolvedValueOnce({ sub: 'u1', type: 'access' });

    await expect(service.refreshAccessToken('tok')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('throws Unauthorized when the stored hash is missing or mismatched (revoked)', async () => {
    const { service, jwtService } = makeDeps({ config: { JWT_SECRET: 'unit-secret' } });
    jwtService.verifyAsync.mockResolvedValueOnce({ sub: 'u1', type: 'refresh' });
    // redisStore has no refresh:u1 entry → revoked.

    await expect(service.refreshAccessToken('tok')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('throws Unauthorized when the user no longer exists', async () => {
    const { service, jwtService, redisStore } = makeDeps({
      config: { JWT_SECRET: 'unit-secret' },
    });
    jwtService.verifyAsync.mockResolvedValueOnce({ sub: 'u-gone', type: 'refresh' });
    const hash = crypto.createHash('sha256').update('tok').digest('hex');
    redisStore.set('refresh:u-gone', hash);
    // usersRepository.findOne returns null (no user configured).

    await expect(service.refreshAccessToken('tok')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('mints a fresh access token on the happy path', async () => {
    const user = { id: 'u-ok', phoneNumber: '+919000000010', role: UserRole.CUSTOMER };
    const { service, jwtService, redisStore } = makeDeps({
      user,
      config: { JWT_SECRET: 'unit-secret' },
    });
    jwtService.verifyAsync.mockResolvedValueOnce({ sub: 'u-ok', type: 'refresh' });
    const hash = crypto.createHash('sha256').update('tok').digest('hex');
    redisStore.set('refresh:u-ok', hash);

    const result = await service.refreshAccessToken('tok');

    expect(result.accessToken).toContain('access');
    expect(result.accessToken).toContain('u-ok');
  });
});

describe('AuthService.getProfile', () => {
  it('throws NotFound when the user is absent', async () => {
    const { service } = makeDeps();
    await expect(service.getProfile('missing')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('maps the entity to the API shape with null/empty defaults', async () => {
    const user = {
      id: 'u-p',
      phoneNumber: '+919000000011',
      name: undefined,
      role: UserRole.CUSTOMER,
      profileImageUrl: undefined,
      hasWorkerProfile: undefined,
      isAvailableForWork: undefined,
    };
    const { service } = makeDeps({ user });

    const profile = await service.getProfile('u-p');

    expect(profile).toEqual({
      id: 'u-p',
      phone: '+919000000011',
      name: '',
      email: null,
      avatar: null,
      role: UserRole.CUSTOMER,
      hasWorkerProfile: false,
      isAvailableForWork: true,
    });
  });

  it('passes through populated profile fields', async () => {
    const user = {
      id: 'u-p2',
      phoneNumber: '+919000000012',
      name: 'Anu',
      role: UserRole.OPERATOR,
      profileImageUrl: 'https://cdn/x.png',
      hasWorkerProfile: true,
      isAvailableForWork: false,
    };
    const { service } = makeDeps({ user });

    const profile = await service.getProfile('u-p2');

    expect(profile.name).toBe('Anu');
    expect(profile.avatar).toBe('https://cdn/x.png');
    expect(profile.hasWorkerProfile).toBe(true);
    expect(profile.isAvailableForWork).toBe(false);
  });
});

describe('AuthService.updatePushToken', () => {
  it('throws NotFound when the user is absent', async () => {
    const { service } = makeDeps();
    await expect(service.updatePushToken('missing', 'fcm-tok')).rejects.toBeInstanceOf(
      NotFoundException,
    );
  });

  it('persists the FCM token on the user and caches it in Redis', async () => {
    const user: any = { id: 'u-fcm', phoneNumber: '+919000000013' };
    const { service, redisService, saved } = makeDeps({ user });

    const result = await service.updatePushToken('u-fcm', 'fcm-tok-123');

    expect(user.fcmToken).toBe('fcm-tok-123');
    expect(saved).toContain(user);
    expect(redisService.cacheFcmToken).toHaveBeenCalledWith('u-fcm', 'fcm-tok-123');
    expect(result.message).toBe('Push token updated');
  });
});

describe('AuthService.adminLogin', () => {
  it('throws Unauthorized when admin credentials are not configured', async () => {
    const { service } = makeDeps({ config: {} });
    await expect(service.adminLogin('admin', 'pw')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('throws Unauthorized when the credentials do not match', async () => {
    const { service } = makeDeps({
      config: { ADMIN_USERNAME: 'root', ADMIN_PASSWORD: 'secret' },
    });
    await expect(service.adminLogin('root', 'wrong')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('signs an ADMIN access token on a credential match', async () => {
    const { service, jwtService } = makeDeps({
      config: { ADMIN_USERNAME: 'root', ADMIN_PASSWORD: 'secret' },
    });

    const result = await service.adminLogin('root', 'secret');

    expect(jwtService.signAsync).toHaveBeenCalledWith(
      expect.objectContaining({
        sub: 'env-admin',
        role: UserRole.ADMIN,
        staffRole: 'SUPER_ADMIN',
      }),
    );
    expect(result.accessToken).toContain('access');
    expect(result.staffRole).toBe('SUPER_ADMIN');
    expect(result.pages.length).toBeGreaterThan(0);
  });
});
