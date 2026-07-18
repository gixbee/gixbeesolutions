import { JwtStrategy } from './jwt.strategy';

/**
 * Unit tests for the passport-jwt JwtStrategy.
 *
 * Two reachable behaviours, testable by injecting a ConfigService stub:
 * - constructor: reads 'JWT_SECRET' from config and falls back to
 *   'fallback-secret' when unset — both paths must construct without throwing
 *   (passport-jwt's Strategy requires a non-empty secretOrKey).
 * - validate(payload): maps the JWT claims to the request-user shape
 *   { userId: payload.sub, phoneNumber, role } — this is what every authed
 *   controller reads off `req.user`.
 *
 * No HTTP request, token signing, or passport runtime is exercised — only the
 * strategy's own logic.
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
    it('maps sub -> userId and forwards phoneNumber + role', async () => {
      const strategy = new JwtStrategy(makeConfig('s'));
      const result = await strategy.validate({
        sub: 'user-42',
        phoneNumber: '+15551234567',
        role: 'WORKER',
      });
      expect(result).toEqual({
        userId: 'user-42',
        phoneNumber: '+15551234567',
        role: 'WORKER',
      });
    });

    it('passes through undefined claims rather than inventing values', async () => {
      const strategy = new JwtStrategy(makeConfig('s'));
      const result = await strategy.validate({ sub: 'only-sub' });
      expect(result).toEqual({
        userId: 'only-sub',
        phoneNumber: undefined,
        role: undefined,
      });
    });
  });
});
