import { AadhaarKycService } from './aadhaar-kyc.service';

function makeService(env: Record<string, string | undefined> = {}) {
  const config: any = {
    get: jest.fn((key: string) => env[key]),
  };
  return new AadhaarKycService(config);
}

describe('AadhaarKycService', () => {
  const creds = {
    AADHAAR_CLIENT_ID: 'sp_client_abc',
    AADHAAR_CLIENT_SECRET: 'sp_bearer_token_xyz',
    NODE_ENV: 'development',
  };

  beforeEach(() => {
    global.fetch = jest.fn();
  });

  it('reports unconfigured without real credentials', () => {
    expect(makeService({}).isConfigured()).toBe(false);
    expect(
      makeService({ AADHAAR_CLIENT_ID: 'placeholder' }).isConfigured(),
    ).toBe(false);
  });

  it('generateOtp calls Surepass and returns clientId', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({
        success: true,
        data: { client_id: 'sess_abc' },
        message: 'OTP sent',
      }),
    });
    const svc = makeService(creds);
    const res = await svc.generateOtp('123456789012');

    expect(res.clientId).toBe('sess_abc');
    const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(url).toContain('/api/v1/aadhaar-v2/generate-otp');
    expect(init.headers.Authorization).toContain('sp_bearer_token_xyz');
    expect(JSON.parse(init.body).id_number).toBe('123456789012');
  });

  it('submitOtp returns masked identity on success', async () => {
    (global.fetch as jest.Mock).mockResolvedValue({
      ok: true,
      json: async () => ({
        success: true,
        data: {
          full_name: 'Anu Sharma',
          masked_aadhaar: 'XXXX-XXXX-1234',
        },
      }),
    });
    const svc = makeService(creds);
    const res = await svc.submitOtp('sess_abc', '654321');
    expect(res.fullName).toBe('Anu Sharma');
    expect(res.maskedAadhaar).toBe('XXXX-XXXX-1234');
  });
});
