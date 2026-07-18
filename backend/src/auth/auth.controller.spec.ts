import { AuthController } from './auth.controller';

/**
 * Unit tests for the AuthController HTTP layer — a thin delegation surface over
 * AuthService. Instantiated directly with a jest-mock service (matching this
 * repo's controller-spec style — no Nest TestingModule, no network). Asserts
 * request→service delegation, the JWT userId source for the guarded routes
 * (req.user.userId, not a body/URL value), the legacy fcm-token alias mapping to
 * updatePushToken, and the admin-login empty-string fallback for missing creds.
 */

function makeController() {
  const authService: any = {
    requestOtp: jest.fn(async () => ({ devOtp: '123456' })),
    verifyOtp: jest.fn(async () => ({ accessToken: 'a', refreshToken: 'r' })),
    refreshAccessToken: jest.fn(async () => ({ accessToken: 'a2' })),
    getProfile: jest.fn(async () => ({ id: 'u-1', name: 'Anu' })),
    updatePushToken: jest.fn(async () => ({ ok: true })),
    adminLogin: jest.fn(async () => ({ accessToken: 'admin-tok' })),
  };
  const controller = new AuthController(authService);
  return { controller, authService };
}

describe('AuthController.requestOtp', () => {
  it('forwards the phone from the body', async () => {
    const { controller, authService } = makeController();
    const res = await controller.requestOtp({ phone: '+919000000000' });
    expect(authService.requestOtp).toHaveBeenCalledWith('+919000000000');
    expect(res).toEqual({ devOtp: '123456' });
  });
});

describe('AuthController.verifyOtp', () => {
  it('forwards phone + otp from the body', async () => {
    const { controller, authService } = makeController();
    const res = await controller.verifyOtp({ phone: '+919000000000', otp: '123456' });
    expect(authService.verifyOtp).toHaveBeenCalledWith('+919000000000', '123456');
    expect(res).toEqual({ accessToken: 'a', refreshToken: 'r' });
  });
});

describe('AuthController.refreshToken', () => {
  it('forwards the refreshToken from the body', async () => {
    const { controller, authService } = makeController();
    await controller.refreshToken({ refreshToken: 'rt' });
    expect(authService.refreshAccessToken).toHaveBeenCalledWith('rt');
  });
});

describe('AuthController.getProfile', () => {
  it('uses the JWT userId (req.user.userId), not any body value', async () => {
    const { controller, authService } = makeController();
    const res = await controller.getProfile({ user: { userId: 'u-7' } });
    expect(authService.getProfile).toHaveBeenCalledWith('u-7');
    expect(res).toEqual({ id: 'u-1', name: 'Anu' });
  });
});

describe('AuthController.updatePushToken', () => {
  it('forwards the authed userId + the pushToken', async () => {
    const { controller, authService } = makeController();
    await controller.updatePushToken({ user: { userId: 'u-7' } }, { pushToken: 'tok-1' });
    expect(authService.updatePushToken).toHaveBeenCalledWith('u-7', 'tok-1');
  });
});

describe('AuthController.updateFcmToken (legacy alias)', () => {
  it('maps the legacy fcmToken body to updatePushToken with the authed userId', async () => {
    const { controller, authService } = makeController();
    await controller.updateFcmToken({ user: { userId: 'u-7' } }, { fcmToken: 'legacy-tok' });
    expect(authService.updatePushToken).toHaveBeenCalledWith('u-7', 'legacy-tok');
  });
});

describe('AuthController.adminLogin', () => {
  it('forwards the provided username + password', async () => {
    const { controller, authService } = makeController();
    await controller.adminLogin({ username: 'admin', password: 'pw' });
    expect(authService.adminLogin).toHaveBeenCalledWith('admin', 'pw');
  });

  it('falls back to empty strings when creds are missing', async () => {
    const { controller, authService } = makeController();
    await controller.adminLogin({});
    expect(authService.adminLogin).toHaveBeenCalledWith('', '');
  });
});
