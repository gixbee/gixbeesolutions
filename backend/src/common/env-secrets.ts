/**
 * Detect committed / bootstrap placeholder secrets so gateway readiness and
 * production boot checks do not treat them as live credentials.
 */
const PLACEHOLDER_PATTERNS = [
  /^placeholder/i,
  /^your[-_]/i,
  /^changeme$/i,
  /^replace-with/i,
  /^super-secret-key-for-gixbee$/i,
];

export function isRealSecret(value: string | undefined | null): boolean {
  if (!value?.trim()) return false;
  const v = value.trim();
  if (v.length < 4) return false;
  return !PLACEHOLDER_PATTERNS.some((p) => p.test(v));
}
