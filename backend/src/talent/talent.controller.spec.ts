import { TalentController } from './talent.controller';

/**
 * Unit tests for the TalentController HTTP layer — a thin delegation over
 * TalentService. Instantiated directly with a jest-mock service (this repo's
 * controller-spec style — no Nest TestingModule, no DB/network). Asserts the JWT
 * `req.user.userId` injection on every route, the whole-body DTO extraction
 * (skills/alerts routes now take AddSkillDto/RemoveSkillDto/ToggleAlertsDto), and
 * the addOrUpdateSkill `Number(rate)` coercion (string rate → number passed to
 * the service).
 */

function makeController() {
  const talentService: any = {
    getProfile: jest.fn(async () => ({ id: 'tp1' })),
    updateProfile: jest.fn(async () => ({ id: 'tp1', headline: 'New' })),
    addOrUpdateSkill: jest.fn(async () => ({ id: 'sk1' })),
    removeSkill: jest.fn(async () => undefined),
    toggleAlerts: jest.fn(async () => ({ id: 'tp1', jobAlertsEnabled: true })),
    getVerificationStatus: jest.fn(() => ({
      provider: 'AADHAAR',
      available: false,
      needsApiKey: true,
      verified: false,
      message: 'coming soon',
    })),
    initiateVerification: jest.fn(() => ({
      status: 'UNAVAILABLE',
      needsApiKey: true,
      provider: 'AADHAAR',
      verified: false,
      message: 'not live yet',
    })),
    generateAadhaarOtp: jest.fn(async () => ({
      status: 'OTP_SENT',
      clientId: 'sess-1',
      verified: false,
      message: 'OTP sent',
    })),
    submitAadhaarOtp: jest.fn(async () => ({
      status: 'VERIFIED',
      verified: true,
      maskedAadhaar: 'XXXX-1234',
      fullName: 'Test User',
      message: 'verified',
    })),
  };
  const controller = new TalentController(talentService);
  return { controller, talentService };
}

const req = { user: { userId: 'me-1' } };

describe('TalentController.getProfile', () => {
  it('delegates to getProfile with the authed userId', async () => {
    const { controller, talentService } = makeController();
    const res = await controller.getProfile(req);
    expect(talentService.getProfile).toHaveBeenCalledWith('me-1');
    expect(res).toEqual({ id: 'tp1' });
  });
});

describe('TalentController.updateProfile', () => {
  it('forwards the authed userId and the body to updateProfile', async () => {
    const { controller, talentService } = makeController();
    // Use UpdateTalentProfileDto-valid fields now that the @Body() is typed.
    const body = { skills: ['Plumbing'], experience: '5 years' };
    await controller.updateProfile(req, body);
    expect(talentService.updateProfile).toHaveBeenCalledWith('me-1', body);
  });
});

describe('TalentController.addOrUpdateSkill', () => {
  it('coerces a string rate to a number and forwards all fields', async () => {
    const { controller, talentService } = makeController();
    const rateChart = { weekday: 100, weekend: 150 };
    await controller.addOrUpdateSkill(req, {
      skillName: 'Plumbing',
      rate: '120' as any,
      bio: 'bio text',
      rateChart,
    });
    expect(talentService.addOrUpdateSkill).toHaveBeenCalledWith(
      'me-1',
      'Plumbing',
      120,
      'bio text',
      rateChart,
    );
    expect(typeof talentService.addOrUpdateSkill.mock.calls[0][2]).toBe(
      'number',
    );
  });
});

describe('TalentController.removeSkill', () => {
  it('forwards the authed userId and the skillId from the body', async () => {
    const { controller, talentService } = makeController();
    await controller.removeSkill(req, { skillId: 'skill-9' });
    expect(talentService.removeSkill).toHaveBeenCalledWith('me-1', 'skill-9');
  });
});

describe('TalentController.toggleAlerts', () => {
  it('forwards the authed userId and the enabled flag', async () => {
    const { controller, talentService } = makeController();
    await controller.toggleAlerts(req, { enabled: false });
    expect(talentService.toggleAlerts).toHaveBeenCalledWith('me-1', false);
  });
});

describe('TalentController.getVerificationStatus', () => {
  it('delegates to the service with the authed userId', async () => {
    const { controller, talentService } = makeController();
    talentService.getVerificationStatus.mockResolvedValue({
      provider: 'AADHAAR',
      needsApiKey: true,
      verified: false,
    });
    const res = await controller.getVerificationStatus(req);
    expect(talentService.getVerificationStatus).toHaveBeenCalledWith('me-1');
    expect(res).toMatchObject({
      provider: 'AADHAAR',
      needsApiKey: true,
      verified: false,
    });
  });
});

describe('TalentController.initiateVerification', () => {
  it('forwards the authed userId and returns the needs-API-key payload', async () => {
    const { controller, talentService } = makeController();
    const res = await controller.initiateVerification(req);
    expect(talentService.initiateVerification).toHaveBeenCalledWith('me-1');
    expect(res).toMatchObject({ status: 'UNAVAILABLE', verified: false });
  });
});

describe('TalentController Aadhaar OTP', () => {
  it('generateAadhaarOtp forwards userId and aadhaar number', async () => {
    const { controller, talentService } = makeController();
    const res = await controller.generateAadhaarOtp(req, {
      aadhaarNumber: '123456789012',
    });
    expect(talentService.generateAadhaarOtp).toHaveBeenCalledWith(
      'me-1',
      '123456789012',
    );
    expect(res.status).toBe('OTP_SENT');
  });

  it('submitAadhaarOtp forwards userId, clientId, and otp', async () => {
    const { controller, talentService } = makeController();
    const res = await controller.submitAadhaarOtp(req, {
      clientId: 'sess-1',
      otp: '654321',
    });
    expect(talentService.submitAadhaarOtp).toHaveBeenCalledWith(
      'me-1',
      'sess-1',
      '654321',
    );
    expect(res.verified).toBe(true);
  });
});
