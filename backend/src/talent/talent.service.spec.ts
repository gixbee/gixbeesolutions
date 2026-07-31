import { NotFoundException } from '@nestjs/common';
import { TalentService } from './talent.service';
import { SkillApprovalStatus } from './professional-skill.entity';

/**
 * Unit tests for the talent/job-seeker profile flow:
 * - getProfile: returns the existing profile, or lazily creates+saves a blank
 *   one keyed to the user when none exists.
 * - addOrUpdateSkill: upserts a ProfessionalSkill — updates rate/bio/rateChart
 *   on an existing skill and RESETS its approval status to PENDING; otherwise
 *   creates a new PENDING skill.
 * - removeSkill / updateSkillStatus: NotFound guards + happy paths.
 * - toggleAlerts: delegates to updateProfile with jobAlertsEnabled.
 * - recordNoShow (DEFECT-010): increments noShowCount and drops searchRank by
 *   10, floored at 0; no-ops when the user has no profile; tolerates null
 *   counters by defaulting (count→0, rank→100).
 *
 * Both repositories are mocked in-memory so each branch can be toggled
 * deterministically; no database is touched.
 */
function makeService(
  opts: {
    profile?: any;
    skill?: any;
    configValues?: Record<string, string>;
  } = {},
) {
  const talentSaved: any[] = [];
  const skillSaved: any[] = [];
  const skillRemoved: any[] = [];

  const talentRepo: any = {
    findOne: jest.fn(async () => opts.profile ?? null),
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (p: any) => {
      talentSaved.push(p);
      return p;
    }),
  };

  const skillRepo: any = {
    findOne: jest.fn(async () => opts.skill ?? null),
    create: jest.fn((dto: any) => ({ ...dto })),
    save: jest.fn(async (s: any) => {
      skillSaved.push(s);
      return s;
    }),
    remove: jest.fn(async (s: any) => {
      skillRemoved.push(s);
      return s;
    }),
  };

  const config: any = {
    get: jest.fn((key: string) => opts.configValues?.[key]),
  };

  const service = new TalentService(talentRepo, skillRepo, config);
  return {
    service,
    talentRepo,
    skillRepo,
    talentSaved,
    skillSaved,
    skillRemoved,
    config,
  };
}

const profile = (over: Partial<any> = {}) => ({
  id: 'profile-1',
  user: { id: 'user-1' },
  noShowCount: 0,
  searchRank: 100,
  jobAlertsEnabled: true,
  ...over,
});

describe('TalentService.getProfile', () => {
  it('returns the existing profile when one is found', async () => {
    const existing = profile();
    const { service, talentRepo, talentSaved } = makeService({
      profile: existing,
    });

    const result = await service.getProfile('user-1');

    expect(result).toBe(existing);
    expect(talentRepo.create).not.toHaveBeenCalled();
    expect(talentSaved).toHaveLength(0);
  });

  it('lazily creates and saves a blank profile keyed to the user when none exists', async () => {
    const { service, talentRepo, talentSaved } = makeService({ profile: null });

    const result = await service.getProfile('user-2');

    expect(talentRepo.create).toHaveBeenCalledWith({ user: { id: 'user-2' } });
    expect(talentSaved).toHaveLength(1);
    expect(result.user.id).toBe('user-2');
  });
});

describe('TalentService.updateProfile', () => {
  it('merges the patch onto the profile and saves it', async () => {
    const existing = profile({ experience: 'old' });
    const { service, talentSaved } = makeService({ profile: existing });

    const result = await service.updateProfile('user-1', { experience: 'new' });

    expect(result.experience).toBe('new');
    expect(talentSaved).toHaveLength(1);
    expect(talentSaved[0].experience).toBe('new');
  });
});

describe('TalentService.addOrUpdateSkill', () => {
  it('updates an existing skill and resets its status to PENDING', async () => {
    const existingSkill = {
      id: 'skill-1',
      name: 'Plumbing',
      hourlyRate: 100,
      bio: 'old bio',
      status: SkillApprovalStatus.APPROVED,
    };
    const { service, skillSaved } = makeService({
      profile: profile(),
      skill: existingSkill,
    });

    const result = await service.addOrUpdateSkill(
      'user-1',
      'Plumbing',
      250,
      'new bio',
      { '1h': 250 },
    );

    expect(result).toBe(existingSkill);
    expect(result.hourlyRate).toBe(250);
    expect(result.bio).toBe('new bio');
    expect(result.rateChart).toEqual({ '1h': 250 });
    expect(result.status).toBe(SkillApprovalStatus.PENDING);
    expect(skillSaved).toHaveLength(1);
  });

  it('keeps the existing rateChart when none is supplied (undefined guard)', async () => {
    const existingSkill = {
      id: 'skill-1',
      name: 'Plumbing',
      hourlyRate: 100,
      bio: 'keep',
      rateChart: { '1h': 100 },
      status: SkillApprovalStatus.APPROVED,
    };
    const { service } = makeService({
      profile: profile(),
      skill: existingSkill,
    });

    const result = await service.addOrUpdateSkill(
      'user-1',
      'Plumbing',
      300,
      undefined as any,
    );

    expect(result.hourlyRate).toBe(300);
    expect(result.rateChart).toEqual({ '1h': 100 });
    expect(result.status).toBe(SkillApprovalStatus.PENDING);
  });

  it('creates a new PENDING skill when none matches', async () => {
    const { service, skillRepo, skillSaved } = makeService({
      profile: profile(),
      skill: null,
    });

    const result = await service.addOrUpdateSkill(
      'user-1',
      'Carpentry',
      180,
      'bio',
    );

    expect(skillRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'Carpentry',
        hourlyRate: 180,
        bio: 'bio',
        status: SkillApprovalStatus.PENDING,
      }),
    );
    expect(skillSaved).toHaveLength(1);
    expect(result.status).toBe(SkillApprovalStatus.PENDING);
  });
});

describe('TalentService.removeSkill', () => {
  it('removes the skill when it belongs to the user profile', async () => {
    const skill = { id: 'skill-1' };
    const { service, skillRemoved } = makeService({
      profile: profile(),
      skill,
    });

    await service.removeSkill('user-1', 'skill-1');

    expect(skillRemoved).toHaveLength(1);
    expect(skillRemoved[0]).toBe(skill);
  });

  it('throws NotFound when the skill is not on the profile', async () => {
    const { service, skillRemoved } = makeService({
      profile: profile(),
      skill: null,
    });

    await expect(
      service.removeSkill('user-1', 'missing'),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(skillRemoved).toHaveLength(0);
  });
});

describe('TalentService.updateSkillStatus', () => {
  it('sets the new status and saves', async () => {
    const skill = { id: 'skill-1', status: SkillApprovalStatus.PENDING };
    const { service, skillSaved } = makeService({ skill });

    const result = await service.updateSkillStatus(
      'skill-1',
      SkillApprovalStatus.APPROVED,
    );

    expect(result.status).toBe(SkillApprovalStatus.APPROVED);
    expect(skillSaved).toHaveLength(1);
  });

  it('throws NotFound for an unknown skill id', async () => {
    const { service } = makeService({ skill: null });

    await expect(
      service.updateSkillStatus('nope', SkillApprovalStatus.APPROVED),
    ).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('TalentService.toggleAlerts', () => {
  it('persists the jobAlertsEnabled flag via updateProfile', async () => {
    const existing = profile({ jobAlertsEnabled: true });
    const { service, talentSaved } = makeService({ profile: existing });

    const result = await service.toggleAlerts('user-1', false);

    expect(result.jobAlertsEnabled).toBe(false);
    expect(talentSaved).toHaveLength(1);
    expect(talentSaved[0].jobAlertsEnabled).toBe(false);
  });
});

describe('TalentService.recordNoShow', () => {
  it('increments noShowCount and drops searchRank by 10', async () => {
    const existing = profile({ noShowCount: 2, searchRank: 80 });
    const { service, talentSaved } = makeService({ profile: existing });

    await service.recordNoShow('user-1');

    expect(talentSaved).toHaveLength(1);
    expect(talentSaved[0].noShowCount).toBe(3);
    expect(talentSaved[0].searchRank).toBe(70);
  });

  it('floors searchRank at 0 and never goes negative', async () => {
    const existing = profile({ noShowCount: 9, searchRank: 5 });
    const { service, talentSaved } = makeService({ profile: existing });

    await service.recordNoShow('user-1');

    expect(talentSaved[0].searchRank).toBe(0);
  });

  it('defaults null counters (count→1, rank→90) on first no-show', async () => {
    const existing = profile({ noShowCount: null, searchRank: null });
    const { service, talentSaved } = makeService({ profile: existing });

    await service.recordNoShow('user-1');

    expect(talentSaved[0].noShowCount).toBe(1);
    expect(talentSaved[0].searchRank).toBe(90);
  });

  it('no-ops silently when the user has no profile', async () => {
    const { service, talentSaved } = makeService({ profile: null });

    await expect(service.recordNoShow('ghost')).resolves.toBeUndefined();
    expect(talentSaved).toHaveLength(0);
  });
});

/**
 * DigiLocker identity-verification stub (Phase 5 — credential-blocked).
 * With no DIGILOCKER_* env vars the status/initiate pair must advertise
 * needsApiKey and NEVER report a verified result; with both creds present
 * (real flow still unwritten) initiate must return NOT_IMPLEMENTED rather
 * than faking a verified identity. `verified` is false in every branch.
 */
describe('TalentService — DigiLocker verification stub', () => {
  const bothCreds = {
    DIGILOCKER_CLIENT_ID: 'cid',
    DIGILOCKER_CLIENT_SECRET: 'secret',
  };

  it('getVerificationStatus reports needsApiKey when unconfigured', () => {
    const { service } = makeService();
    const status = service.getVerificationStatus();
    expect(status.provider).toBe('DIGILOCKER');
    expect(status.available).toBe(false);
    expect(status.needsApiKey).toBe(true);
    expect(status.verified).toBe(false);
    expect(status.message).toContain('coming soon');
  });

  it('getVerificationStatus reports available (still not verified) when both creds exist', () => {
    const { service } = makeService({ configValues: bothCreds });
    const status = service.getVerificationStatus();
    expect(status.available).toBe(true);
    expect(status.needsApiKey).toBe(false);
    expect(status.verified).toBe(false);
    expect(status.message).toBeNull();
  });

  it('treats a partial credential set as unconfigured', () => {
    const { service } = makeService({
      configValues: { DIGILOCKER_CLIENT_ID: 'cid' }, // secret missing
    });
    expect(service.getVerificationStatus().available).toBe(false);
  });

  it('initiateVerification returns a needs-API-key payload (never verified) when unconfigured', () => {
    const { service } = makeService();
    const res = service.initiateVerification('user-1');
    expect(res.status).toBe('UNAVAILABLE');
    expect(res.needsApiKey).toBe(true);
    expect(res.verified).toBe(false);
    expect(res.provider).toBe('DIGILOCKER');
  });

  it('initiateVerification returns NOT_IMPLEMENTED (never verified) when creds exist', () => {
    const { service } = makeService({ configValues: bothCreds });
    const res = service.initiateVerification('user-1');
    expect(res.status).toBe('NOT_IMPLEMENTED');
    expect(res.needsApiKey).toBe(false);
    expect(res.verified).toBe(false);
  });
});
