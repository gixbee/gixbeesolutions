import { redisAllowsMemoryFallback } from './redis-fallback';

describe('redisAllowsMemoryFallback', () => {
  const prev = process.env.NODE_ENV;

  afterEach(() => {
    process.env.NODE_ENV = prev;
  });

  function cfg(value: string | undefined) {
    return { get: (key: string) => (key === 'REDIS_ALLOW_MEMORY_FALLBACK' ? value : undefined) };
  }

  it('honours an explicit true flag even in production', () => {
    process.env.NODE_ENV = 'production';
    expect(redisAllowsMemoryFallback(cfg('true'))).toBe(true);
  });

  it('honours an explicit false flag even outside production', () => {
    process.env.NODE_ENV = 'development';
    expect(redisAllowsMemoryFallback(cfg('false'))).toBe(false);
  });

  it('defaults to false in production when the flag is unset', () => {
    process.env.NODE_ENV = 'production';
    expect(redisAllowsMemoryFallback(cfg(undefined))).toBe(false);
  });

  it('defaults to true outside production when the flag is unset', () => {
    process.env.NODE_ENV = 'development';
    expect(redisAllowsMemoryFallback(cfg(undefined))).toBe(true);
  });
});
