import { NotificationsController } from './notifications.controller';

/**
 * Unit tests for the NotificationsController HTTP layer — a thin delegation over
 * NotificationsService. Instantiated directly with a jest-mock service (this
 * repo's controller-spec style — no Nest TestingModule, no Firebase/network).
 * Asserts: health→getDiagnostics, test-self→testPushToUser with the JWT userId,
 * and the public `test` route's sendToDevice payload mapping including the
 * title/body default fallbacks and the success/failure message mapping.
 */

function makeController(sendResult = true) {
  const notificationsService: any = {
    getDiagnostics: jest.fn(() => ({ ready: true })),
    testPushToUser: jest.fn(async () => ({ sent: true })),
    sendToDevice: jest.fn(async () => sendResult),
  };
  const controller = new NotificationsController(notificationsService);
  return { controller, notificationsService };
}

describe('NotificationsController.getHealth', () => {
  it('delegates to getDiagnostics', async () => {
    const { controller, notificationsService } = makeController();
    const res = await controller.getHealth();
    expect(notificationsService.getDiagnostics).toHaveBeenCalledTimes(1);
    expect(res).toEqual({ ready: true });
  });
});

describe('NotificationsController.testSelfPush', () => {
  it('forwards the authed userId to testPushToUser', async () => {
    const { controller, notificationsService } = makeController();
    const res = await controller.testSelfPush({ user: { userId: 'me-1' } });
    expect(notificationsService.testPushToUser).toHaveBeenCalledWith('me-1');
    expect(res).toEqual({ sent: true });
  });
});

describe('NotificationsController.sendTestNotification', () => {
  it('maps the body to a sendToDevice payload and returns a success message', async () => {
    const { controller, notificationsService } = makeController(true);
    const res = await controller.sendTestNotification({
      fcmToken: 'tok-1',
      title: 'Hi',
      message: 'body text',
      data: { k: 'v' },
    });
    expect(notificationsService.sendToDevice).toHaveBeenCalledWith({
      fcmToken: 'tok-1',
      title: 'Hi',
      body: 'body text',
      data: { k: 'v' },
    });
    expect(res).toEqual({
      success: true,
      message: 'Notification sent successfully',
    });
  });

  it('applies default title/body when they are omitted', async () => {
    const { controller, notificationsService } = makeController(true);
    await controller.sendTestNotification({ fcmToken: 'tok-1' } as any);
    expect(notificationsService.sendToDevice).toHaveBeenCalledWith({
      fcmToken: 'tok-1',
      title: 'Test Notification',
      body: 'This is a test push notification from Gixbee Backend.',
      data: undefined,
    });
  });

  it('returns the failure message when sendToDevice resolves false', async () => {
    const { controller } = makeController(false);
    const res = await controller.sendTestNotification({
      fcmToken: 'tok-1',
      title: 'Hi',
      message: 'b',
    });
    expect(res).toEqual({
      success: false,
      message: 'Failed to send notification. Check backend logs.',
    });
  });
});
