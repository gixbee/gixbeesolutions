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
      provider: 'DIGILOCKER',
      available: false,
      needsApiKey: true,
      verified: false,
      message: 'coming soon',
    })),
    initiateVerification: jest.fn(() => ({
      status: 'UNAVAILABLE',
      needsApiKey: true,
      provider: 'DIGILOCKER',
      verified: false,
      message: 'not live yet',
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
    expect(typeof talentService.addOrUpdateSkill.mock.calls[0][2]).toBe('number');
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
  it('delegates to the service (no body, no user needed) and returns the stub status', () => {
    const { controller, talentService } = makeController();
    const res = controller.getVerificationStatus();
    expect(talentService.getVerificationStatus).toHaveBeenCalled();
    expect(res).toMatchObject({ provider: 'DIGILOCKER', needsApiKey: true, verified: false });
  });
});

describe('TalentController.initiateVerification', () => {
  it('forwards the authed userId and returns the needs-API-key payload', () => {
    const { controller, talentService } = makeController();
    const res = controller.initiateVerification(req);
    expect(talentService.initiateVerification).toHaveBeenCalledWith('me-1');
    expect(res).toMatchObject({ status: 'UNAVAILABLE', verified: false });
  });
});
