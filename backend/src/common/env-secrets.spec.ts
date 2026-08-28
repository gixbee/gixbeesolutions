import { isRealSecret } from './env-secrets';

describe('isRealSecret', () => {
  it('rejects empty and placeholder values', () => {
    expect(isRealSecret('')).toBe(false);
    expect(isRealSecret('placeholder_key_id')).toBe(false);
    expect(isRealSecret('your_msg91_key')).toBe(false);
    expect(isRealSecret('changeme')).toBe(false);
  });

  it('accepts real-looking secrets', () => {
    expect(isRealSecret('rzp_live_AbCdEf123456')).toBe(true);
    expect(isRealSecret('sk_live_abc123def456ghi789')).toBe(true);
  });
});
