import { SmsService } from './sms.service';

function makeService(env: Record<string, string | undefined> = {}) {
  const config: any = {
    get: jest.fn((key: string) => env[key]),
  };
  return new SmsService(config);
}

describe('SmsService', () => {
  const realEnv = {
    MSG91_AUTH_KEY: 'live_auth_key_abc123',
    MSG91_TEMPLATE_ID: 'tmpl_12345',
    MSG91_SENDER_ID: 'GIXBEE',
    NODE_ENV: 'production',
  };

  beforeEach(() => {
    global.fetch = jest.fn();
  });

  it('reports unconfigured when keys are missing or placeholders', () => {
    expect(makeService({}).isConfigured()).toBe(false);
    expect(
      makeService({ MSG91_AUTH_KEY: 'placeholder_key' }).isConfigured(),
    ).toBe(false);
  });

  it('reports configured with real auth key + template id', () => {
    expect(makeService(realEnv).isConfigured()).toBe(true);
  });

  it('normalizes Indian phone numbers to 91XXXXXXXXXX', () => {
    const svc = makeService({});
    expect(svc.normalizeMobile('+919876543210')).toBe('919876543210');
    expect(svc.normalizeMobile('9876543210')).toBe('919876543210');
  });

  it('calls MSG91 flow API when configured', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      text: async () => '{"type":"success"}',
    });
    const svc = makeService(realEnv);
    await svc.sendOtp('+919876543210', '654321');

    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(url).toBe('https://control.msg91.com/api/v5/flow/');
    expect(init.headers.authkey).toBe('live_auth_key_abc123');
    const payload = JSON.parse(init.body);
    expect(payload.template_id).toBe('tmpl_12345');
    expect(payload.recipients[0].mobiles).toBe('919876543210');
    expect(payload.recipients[0].OTP).toBe('654321');
  });

  it('skips fetch when unconfigured in development', async () => {
    const svc = makeService({ NODE_ENV: 'development' });
    await svc.sendOtp('+919876543210', '111111');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('throws when MSG91 returns a non-2xx response', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: false,
      status: 400,
      text: async () => 'bad template',
    });
    const svc = makeService(realEnv);
    await expect(svc.sendOtp('+919876543210', '111111')).rejects.toThrow(
      'SMS delivery failed',
    );
  });
});
