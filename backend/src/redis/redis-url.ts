/**
 * Shared Redis URL builder — used by RedisService and RedisIoAdapter so
 * REDIS_URL vs REDIS_HOST/PORT/PASSWORD never drift between clients.
 */
export function buildRedisUrl(config: {
  get<T = string>(key: string): T | undefined;
}): string {
  const redisUrl = config.get<string>('REDIS_URL');
  if (redisUrl) return redisUrl;

  const host = config.get<string>('REDIS_HOST') || 'localhost';
  const port = config.get<number>('REDIS_PORT') || 6379;
  const password = config.get<string>('REDIS_PASSWORD');

  return password
    ? `redis://:${password}@${host}:${port}`
    : `redis://${host}:${port}`;
}
