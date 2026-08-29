import { UsersController } from './users.controller';
import { UserApprovalStatus, UserRole } from './user.entity';
import { SkillApprovalStatus } from '../talent/professional-skill.entity';

/**
 * Unit tests for the UsersController HTTP layer (the admin-user-list surface) —
 * a thin delegation over UsersService + TalentService. Instantiated directly
 * with jest-mock services (matching this repo's controller-spec style — no Nest
 * TestingModule, no network). Asserts request→service delegation, URL :id
 * forwarding, the fcm-token "token required" guard, and the skill-status route
 * delegating to TalentService rather than UsersService.
 */

function makeController() {
  const usersService: any = {
    getSystemSummary: jest.fn(async () => ({ total: 3 })),
    findAll: jest.fn(async () => [{ id: 'u1' }, { id: 'u2' }]),
    searchUsers: jest.fn(async () => [{ id: 'u1', name: 'Anu' }]),
    findById: jest.fn(async () => ({ id: 'u1' })),
    getUserStats: jest.fn(async () => ({ bookings: 5 })),
    updateProfile: jest.fn(async () => ({ id: 'u1', name: 'New' })),
    updateFcmToken: jest.fn(async () => ({ ok: true })),
    updateApprovalStatus: jest.fn(async () => ({
      id: 'u1',
      approvalStatus: 'APPROVED',
    })),
    updateVerification: jest.fn(async () => ({ id: 'u1', isVerified: true })),
  };
  const talentService: any = {
    updateSkillStatus: jest.fn(async () => ({ id: 's1', status: 'APPROVED' })),
  };
  const controller = new UsersController(usersService, talentService);
  return { controller, usersService, talentService };
}

describe('UsersController.getSummary', () => {
  it('delegates to getSystemSummary', async () => {
    const { controller, usersService } = makeController();
    const res = await controller.getSummary();
    expect(usersService.getSystemSummary).toHaveBeenCalledTimes(1);
    expect(res).toEqual({ total: 3 });
  });
});

describe('UsersController.getAllUsers', () => {
  it('forwards parsed page/limit to the service', async () => {
    const { controller, usersService } = makeController();
    const res = await controller.getAllUsers('2', '20');
    expect(usersService.findAll).toHaveBeenCalledWith(2, 20);
    expect(res).toEqual([{ id: 'u1' }, { id: 'u2' }]);
  });

  it('defaults to page 1 / limit 50 when query params are omitted', async () => {
    const { controller, usersService } = makeController();
    await controller.getAllUsers();
    expect(usersService.findAll).toHaveBeenCalledWith(1, 50);
  });
});

describe('UsersController.searchUsers', () => {
  it('forwards the q query param and a parsed limit to searchUsers', async () => {
    const { controller, usersService } = makeController();
    const req = { user: { role: UserRole.CUSTOMER } };
    const res = await controller.searchUsers('anu', '5', req);
    expect(usersService.searchUsers).toHaveBeenCalledWith('anu', 5, {
      includePhone: false,
    });
    expect(res).toEqual([{ id: 'u1', name: 'Anu' }]);
  });

  it('defaults limit to 20 when the limit param is omitted', async () => {
    const { controller, usersService } = makeController();
    await controller.searchUsers('anu', undefined, {
      user: { role: UserRole.ADMIN, staffRole: 'SUPER_ADMIN' },
    });
    expect(usersService.searchUsers).toHaveBeenCalledWith('anu', 20, {
      includePhone: true,
    });
  });

  it('does not include phone for mobile JWT with orphan role=ADMIN', async () => {
    const { controller, usersService } = makeController();
    await controller.searchUsers('anu', '5', {
      user: { role: UserRole.ADMIN },
    });
    expect(usersService.searchUsers).toHaveBeenCalledWith('anu', 5, {
      includePhone: false,
    });
  });

  it('falls back to 20 when limit is non-numeric, and coerces a missing q to ""', async () => {
    const { controller, usersService } = makeController();
    await controller.searchUsers(undefined as any, 'abc', {
      user: { role: UserRole.CUSTOMER },
    });
    expect(usersService.searchUsers).toHaveBeenCalledWith('', 20, {
      includePhone: false,
    });
  });
});

describe('UsersController.getUser', () => {
  it('forwards the URL :id to findById for self', async () => {
    const { controller, usersService } = makeController();
    const res = await controller.getUser('u-42', {
      user: { userId: 'u-42', role: UserRole.CUSTOMER },
    });
    expect(usersService.findById).toHaveBeenCalledWith('u-42');
    expect(res).toEqual({ id: 'u1' });
  });

  it('rejects lookup of another user for non-admin JWT', async () => {
    const { controller, usersService } = makeController();
    await expect(
      controller.getUser('other', {
        user: { userId: 'u-42', role: UserRole.CUSTOMER },
      }),
    ).rejects.toThrow('You can only view your own profile');
    expect(usersService.findById).not.toHaveBeenCalled();
  });

  it('rejects orphan role=ADMIN mobile JWT reading another user', async () => {
    const { controller, usersService } = makeController();
    await expect(
      controller.getUser('other', {
        user: { userId: 'u-42', role: UserRole.ADMIN },
      }),
    ).rejects.toThrow('You can only view your own profile');
    expect(usersService.findById).not.toHaveBeenCalled();
  });
});

describe('UsersController.getUserStats', () => {
  it('forwards the URL :id to getUserStats for self', async () => {
    const { controller, usersService } = makeController();
    await controller.getUserStats('u-42', {
      user: { userId: 'u-42', role: UserRole.CUSTOMER },
    });
    expect(usersService.getUserStats).toHaveBeenCalledWith('u-42');
  });

  it('rejects stats for another user without portal admin session', async () => {
    const { controller, usersService } = makeController();
    await expect(
      controller.getUserStats('other', {
        user: { userId: 'u-42', role: UserRole.CUSTOMER },
      }),
    ).rejects.toThrow('You can only view your own stats');
    expect(usersService.getUserStats).not.toHaveBeenCalled();
  });

  it('allows portal admin to read another user stats', async () => {
    const { controller, usersService } = makeController();
    await controller.getUserStats('other', {
      user: {
        userId: 'admin-1',
        role: UserRole.ADMIN,
        staffRole: 'SUPER_ADMIN',
      },
    });
    expect(usersService.getUserStats).toHaveBeenCalledWith('other');
  });
});

describe('UsersController.updateProfile', () => {
  it('forwards self profile fields without privileged keys', async () => {
    const { controller, usersService } = makeController();
    const body = { name: 'New' };
    await controller.updateProfile('u-42', { user: { userId: 'u-42', role: UserRole.CUSTOMER } }, body);
    expect(usersService.updateProfile).toHaveBeenCalledWith('u-42', body, {
      allowPrivilegedFields: false,
    });
  });

  it('rejects self-service role escalation', async () => {
    const { controller, usersService } = makeController();
    await expect(
      controller.updateProfile(
        'u-42',
        { user: { userId: 'u-42', role: UserRole.CUSTOMER } },
        { role: UserRole.ADMIN },
      ),
    ).rejects.toThrow('Only admins can change role or worker profile');
    expect(usersService.updateProfile).not.toHaveBeenCalled();
  });

  it('allows portal admin to patch role on any user', async () => {
    const { controller, usersService } = makeController();
    const body = { name: 'New', role: UserRole.OWNER, hasWorkerProfile: true };
    await controller.updateProfile(
      'u-42',
      {
        user: {
          userId: 'admin-1',
          role: UserRole.ADMIN,
          staffRole: 'SUPER_ADMIN',
        },
      },
      body,
    );
    expect(usersService.updateProfile).toHaveBeenCalledWith('u-42', body, {
      allowPrivilegedFields: true,
    });
  });
});

describe('UsersController.updateFcmToken', () => {
  it('forwards :id + token when present', async () => {
    const { controller, usersService } = makeController();
    await controller.updateFcmToken(
      'u-42',
      { user: { userId: 'u-42', role: UserRole.CUSTOMER } },
      { token: 'tok-1' } as any,
    );
    expect(usersService.updateFcmToken).toHaveBeenCalledWith('u-42', 'tok-1');
  });

  it('throws when the token is missing and never calls the service', async () => {
    const { controller, usersService } = makeController();
    await expect(
      controller.updateFcmToken(
        'u-42',
        { user: { userId: 'u-42', role: UserRole.CUSTOMER } },
        { token: '' } as any,
      ),
    ).rejects.toThrow('FCM token is required');
    expect(usersService.updateFcmToken).not.toHaveBeenCalled();
  });
});

describe('UsersController.updateSkillStatus', () => {
  it('delegates to TalentService (not UsersService) with skillId + status', async () => {
    const { controller, talentService, usersService } = makeController();
    await controller.updateSkillStatus('s-1', {
      status: SkillApprovalStatus.APPROVED,
    } as any);
    expect(talentService.updateSkillStatus).toHaveBeenCalledWith(
      's-1',
      SkillApprovalStatus.APPROVED,
    );
    expect(usersService.updateApprovalStatus).not.toHaveBeenCalled();
  });
});

describe('UsersController.updateStatus', () => {
  it('forwards :id + approval status', async () => {
    const { controller, usersService } = makeController();
    await controller.updateStatus('u-42', {
      status: UserApprovalStatus.APPROVED,
    } as any);
    expect(usersService.updateApprovalStatus).toHaveBeenCalledWith(
      'u-42',
      UserApprovalStatus.APPROVED,
    );
  });
});

describe('UsersController.verifyUser', () => {
  it('forwards :id + the isVerified flag', async () => {
    const { controller, usersService } = makeController();
    await controller.verifyUser('u-42', { isVerified: true } as any);
    expect(usersService.updateVerification).toHaveBeenCalledWith('u-42', true);
  });
});
