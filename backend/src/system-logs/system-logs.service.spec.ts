import { SystemLogsService } from './system-logs.service';

/**
 * The retention sweep is armed by a timer inside every backend replica, so
 * with `replicas: 2` two processes wake up for the same window. These tests
 * cover the Redis lock that elects a single runner, plus the retention-days
 * config parsing that decides whether the sweep is armed at all.
 *
 * No database or Redis is touched — the repository and RedisService are stubs.
 */

/** Shared lock state so several service instances behave like separate replicas. */
function makeSharedRedis() {
  const held = new Set<string>();
  return {
    held,
    acquireLock: jest.fn(async (key: string) => {
      if (held.has(key)) return false;
      held.add(key);
      return true;
    }),
  };
}

function makeService(
  redis: { acquireLock: jest.Mock },
  env: Record<string, string | undefined> = {},
) {
  const repo: any = {
    delete: jest.fn(async () => ({ affected: 3 })),
    create: jest.fn((v: any) => v),
    insert: jest.fn(async () => undefined),
  };
  const config: any = { get: jest.fn((key: string) => env[key]) };
  const svc = new SystemLogsService(repo, redis as any, config);
  return { svc, repo };
}

/** Runs the boot-delay timer and awaits the async work it kicked off. */
async function runBootSweep(svc: SystemLogsService) {
  svc.onModuleInit();
  jest.advanceTimersByTime(60_000);
  await Promise.resolve();
  await Promise.resolve();
  svc.onModuleDestroy();
}

describe('SystemLogsService auto-purge', () => {
  beforeEach(() => {
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('purges from exactly one replica when two arm the same window', async () => {
    const redis = makeSharedRedis();
    const a = makeService(redis);
    const b = makeService(redis);

    await runBootSweep(a.svc);
    await runBootSweep(b.svc);

    expect(redis.acquireLock).toHaveBeenCalledTimes(2);
    const purges = [a.repo.delete, b.repo.delete].filter(
      (d) => d.mock.calls.length > 0,
    );
    expect(purges).toHaveLength(1);
  });

  it('purges with the configured retention cutoff', async () => {
    const redis = makeSharedRedis();
    const { svc, repo } = makeService(redis, { LOG_RETENTION_DAYS: '7' });
    jest.setSystemTime(new Date('2026-06-20T00:00:00Z').getTime());

    await runBootSweep(svc);

    expect(repo.delete).toHaveBeenCalledTimes(1);
    // Sweep runs 60s after boot, so the cutoff trails the boot time by that much.
    const cutoff = repo.delete.mock.calls[0][0].createdAt._value as Date;
    expect(cutoff.toISOString()).toBe('2026-06-13T00:01:00.000Z');
  });

  it('never arms the sweep when retention is disabled', async () => {
    const redis = makeSharedRedis();
    const { svc, repo } = makeService(redis, { LOG_RETENTION_DAYS: '0' });

    await runBootSweep(svc);

    expect(redis.acquireLock).not.toHaveBeenCalled();
    expect(repo.delete).not.toHaveBeenCalled();
  });

  it('swallows a failing sweep so the timer keeps running', async () => {
    const redis = makeSharedRedis();
    const { svc, repo } = makeService(redis);
    repo.delete.mockRejectedValueOnce(new Error('table missing'));

    await expect(runBootSweep(svc)).resolves.toBeUndefined();
  });
});
