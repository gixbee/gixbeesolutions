/**
 * Strip private User fields from any payload that will be CACHED and later
 * returned as plain JSON.
 *
 * Why this exists: `@Exclude()` on User.fcmToken/walletBalance is enforced by
 * the global ClassSerializerInterceptor, which only transforms real entity
 * INSTANCES. Anything we JSON.stringify into Redis comes back as a plain
 * object, so the interceptor would no longer strip those fields — the audit's
 * data-leak fix would silently regress for cached feeds.
 *
 * Call this on any entity (or array) before writing it to the cache.
 */
const PRIVATE_USER_FIELDS = ['fcmToken', 'walletBalance'];

export function stripPrivateFields<T>(input: T): T {
  const seen = new WeakSet<object>();

  const walk = (value: any): any => {
    if (value === null || typeof value !== 'object') return value;
    if (value instanceof Date) return value;
    if (seen.has(value)) return value;
    seen.add(value);

    if (Array.isArray(value)) {
      value.forEach(walk);
      return value;
    }

    for (const field of PRIVATE_USER_FIELDS) {
      if (field in value) delete value[field];
    }
    for (const key of Object.keys(value)) {
      walk(value[key]);
    }
    return value;
  };

  // Work on a structural copy so we never mutate live entities.
  return walk(JSON.parse(JSON.stringify(input))) as T;
}
