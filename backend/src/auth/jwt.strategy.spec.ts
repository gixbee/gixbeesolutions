import { JwtStrategy } from './jwt.strategy';

/**
 * Unit tests for the passport-jwt JwtStrategy.
 *
 * - constructor: reads JWT_SECRET (fallback when unset).
 * - validate(payload): maps JWT claims to req.user shape used by guards/controllers.
 */

function makeConfig(secret?: string) {
  return {
    get: jest.fn((_key: string) => secret),
  } as any;
}

describe('JwtStrategy', () => {
  describe('constructor', () => {
    it('reads JWT_SECRET from config', () => {
      const config = makeConfig('s3cr3t');
      const strategy = new JwtStrategy(config);
      expect(config.get).toHaveBeenCalledWith('JWT_SECRET');
      expect(strategy).toBeInstanceOf(JwtStrategy);
    });

    it('constructs with the fallback secret when JWT_SECRET is unset', () => {
      const config = makeConfig(undefined);
      expect(() => new JwtStrategy(config)).not.toThrow();
      expect(config.get).toHaveBeenCalledWith('JWT_SECRET');
    });
  });

  describe('validate', () => {
    it('maps sub -> userId and forwards app + staff claims', async () => {
      const strategy = new JwtStrategy(makeConfig('s'));
      const result = await strategy.validate({
        sub: 'user-42',
        phoneNumber: '+15551234567',
        role: 'WORKER',
        staffRole: 'ADMIN',
        pages: ['bookings', 'users'],
        username: 'asha',
        displayName: 'Asha',
      });
      expect(result).toEqual({
        userId: 'user-42',
        phoneNumber: '+15551234567',
        role: 'WORKER',
        staffRole: 'ADMIN',
        pages: ['bookings', 'users'],
        username: 'asha',
        displayName: 'Asha',
      });
    });

    it('defaults pages to [] and leaves optional claims undefined', async () => {
      const strategy = new JwtStrategy(makeConfig('s'));
      const result = await strategy.validate({ sub: 'only-sub' });
      expect(result).toEqual({
        userId: 'only-sub',
        phoneNumber: undefined,
        role: undefined,
        staffRole: undefined,
        pages: [],
        username: undefined,
        displayName: undefined,
      });
    });
  });
});
