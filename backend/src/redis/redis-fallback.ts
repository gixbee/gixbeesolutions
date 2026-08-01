import { ConfigService } from '@nestjs/config';

/**
 * Whether RedisService / Socket.IO may degrade to process-local memory.
 *
 * Explicit `REDIS_ALLOW_MEMORY_FALLBACK=true|false` wins. Otherwise memory
 * fallback is allowed only outside production — with `replicas: 2`, a silent
 * per-process store splits OTP, locks, and WebSocket rooms across instances.
 */
export function redisAllowsMemoryFallback(
  config: ConfigService | { get: (key: string) => string | undefined },
): boolean {
  const flag = (config.get('REDIS_ALLOW_MEMORY_FALLBACK') ?? '')
    .toString()
    .trim()
    .toLowerCase();
  if (flag === 'true' || flag === '1' || flag === 'yes') return true;
  if (flag === 'false' || flag === '0' || flag === 'no') return false;
  return (process.env.NODE_ENV ?? 'development') !== 'production';
}
