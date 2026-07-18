import { NotificationsService } from './notifications.service';

/**
 * Unit tests for the push-notification service (FCM via Firebase Admin SDK).
 *
 * The Firebase `messaging` handle is a private field normally assigned in
 * onModuleInit() from `admin.messaging()`. Tests inject a stub directly
 * (`(service as any).messaging = ...`) so no real Firebase app is created and
 * no network call is made. The User repository + Redis cache are stubbed too,
 * so every branch toggles deterministically against in-memory state.
 *
 * Coverage:
 * - getDiagnostics: reflects messaging-initialised flag + credential presence.
 * - sendToDevice: null-messaging short-circuit; success shape (data defaults to
 *   {}); stale-token error code → clearStaleToken UPDATE + false; other error
 *   → false with NO token clear.
 * - sendToUser: Redis cache-hit fast path (DB skipped); cache-miss → DB no
 *   token → false; cache-miss → DB token → re-caches Redis + sends.
 * - sendToUsers (multicast): null-messaging / empty-array / no-tokens early
 *   returns; success logs; stale responses trigger per-token clearStaleToken.
 * - testPushToUser: Redis-found path; DB user-not-found; DB token-null; send
 *   success; Firebase send error captured.
 * - notify* helpers: each forwards the right title/body/data to sendToUser.
 */

// A chainable query-builder mock covering BOTH chains the service uses:
//   sendToUsers:     createQueryBuilder('user').select([...]).where().andWhere().getMany()
//   clearStaleToken: createQueryBuilder().update(User).set().where().execute()
function makeQb(rows: any[] = []) {
  const qb: any = {
    select: jest.fn(() => qb),
    where: jest.fn(() => qb),
    andWhere: jest.fn(() => qb),
    update: jest.fn(() => qb),
    set: jest.fn(() => qb),
    getMany: jest.fn(async () => rows),
    execute: jest.fn(async () => ({ affected: rows.length })),
  };
  return qb;
}

function makeService(
  opts: {
    messaging?: any;
    cachedToken?: string | null;
    dbUser?: any;
    qbRows?: any[];
  } = {},
) {
  const qb = makeQb(opts.qbRows ?? []);

  const usersRepository: any = {
    findOne: jest.fn(async () => opts.dbUser ?? null),
    createQueryBuilder: jest.fn(() => qb),
  };

  const redisService: any = {
    getCachedFcmToken: jest.fn(async () =>
      opts.cachedToken === undefined ? null : opts.cachedToken,
    ),
    cacheFcmToken: jest.fn(async () => undefined),
  };

  const configService: any = {
    get: jest.fn((key: string) => {
      const map: Record<string, string> = {
        FIREBASE_PROJECT_ID: 'gixbee-test',
        FIREBASE_CLIENT_EMAIL: 'svc@gixbee-test.iam',
        FIREBASE_PRIVATE_KEY: 'PEM',
      };
      return map[key];
    }),
  };

  const service = new NotificationsService(configService, usersRepository, redisService);
  if (opts.messaging !== undefined) {
    (service as any).messaging = opts.messaging;
  }
  // silence the logger so test output stays clean
  (service as any).logger = { log: jest.fn(), warn: jest.fn(), error: jest.fn() };

  return { service, usersRepository, redisService, configService, qb };
}

function okMessaging(): any {
  return {
    send: jest.fn(async () => 'msg-id-123'),
    sendEachForMulticast: jest.fn(async () => ({
      successCount: 1,
      responses: [{ success: true }],
    })),
  };
}

describe('NotificationsService.getDiagnostics', () => {
  it('reports firebase initialised + credential flags when messaging is set', () => {
    const { service } = makeService({ messaging: okMessaging() });
    const d = service.getDiagnostics();
    expect(d.firebaseInitialized).toBe(true);
    expect(d.credentials.hasProjectId).toBe(true);
    expect(d.credentials.hasClientEmail).toBe(true);
    expect(d.credentials.hasPrivateKey).toBe(true);
    expect(d.credentials.projectId).toBe('gixbee-test');
  });

  it('reports not-initialised when messaging is null', () => {
    const { service } = makeService({ messaging: null });
    expect(service.getDiagnostics().firebaseInitialized).toBe(false);
  });
});

describe('NotificationsService.sendToDevice', () => {
  it('short-circuits to false when messaging is not initialised', async () => {
    const { service } = makeService({ messaging: null });
    const ok = await service.sendToDevice({ fcmToken: 't', title: 'T', body: 'B' });
    expect(ok).toBe(false);
  });

  it('sends and returns true, defaulting data to {} when omitted', async () => {
    const messaging = okMessaging();
    const { service } = makeService({ messaging });
    const ok = await service.sendToDevice({ fcmToken: 'tok', title: 'Hi', body: 'There' });
    expect(ok).toBe(true);
    expect(messaging.send).toHaveBeenCalledTimes(1);
    const msg = messaging.send.mock.calls[0][0];
    expect(msg.token).toBe('tok');
    expect(msg.notification).toEqual({ title: 'Hi', body: 'There' });
    expect(msg.data).toEqual({});
    expect(msg.android.notification.channelId).toBe('gixbee_high_importance');
  });

  it('passes through the supplied data map', async () => {
    const messaging = okMessaging();
    const { service } = makeService({ messaging });
    await service.sendToDevice({
      fcmToken: 'tok',
      title: 'Hi',
      body: 'B',
      data: { type: 'new_booking', bookingId: 'b1' },
    });
    expect(messaging.send.mock.calls[0][0].data).toEqual({
      type: 'new_booking',
      bookingId: 'b1',
    });
  });

  it('clears the stale token and returns false on a not-registered error', async () => {
    const messaging = okMessaging();
    messaging.send = jest.fn(async () => {
      throw { errorInfo: { code: 'messaging/registration-token-not-registered' } };
    });
    const { service, usersRepository, qb } = makeService({ messaging });
    const ok = await service.sendToDevice({ fcmToken: 'stale-tok', title: 'T', body: 'B' });
    expect(ok).toBe(false);
    // clearStaleToken ran its UPDATE … WHERE fcmToken = :fcmToken
    expect(usersRepository.createQueryBuilder).toHaveBeenCalled();
    expect(qb.update).toHaveBeenCalled();
    expect(qb.set).toHaveBeenCalledWith({ fcmToken: null });
    expect(qb.execute).toHaveBeenCalled();
  });

  it('clears the stale token on an invalid-registration-token error', async () => {
    const messaging = okMessaging();
    messaging.send = jest.fn(async () => {
      throw { errorInfo: { code: 'messaging/invalid-registration-token' } };
    });
    const { service, qb } = makeService({ messaging });
    const ok = await service.sendToDevice({ fcmToken: 'bad', title: 'T', body: 'B' });
    expect(ok).toBe(false);
    expect(qb.execute).toHaveBeenCalled();
  });

  it('returns false WITHOUT clearing the token on an unrelated error', async () => {
    const messaging = okMessaging();
    messaging.send = jest.fn(async () => {
      throw { errorInfo: { code: 'messaging/internal-error' }, message: 'boom' };
    });
    const { service, usersRepository } = makeService({ messaging });
    const ok = await service.sendToDevice({ fcmToken: 'tok', title: 'T', body: 'B' });
    expect(ok).toBe(false);
    expect(usersRepository.createQueryBuilder).not.toHaveBeenCalled();
  });
});

describe('NotificationsService.sendToUser', () => {
  it('uses the Redis-cached token and never touches the DB', async () => {
    const messaging = okMessaging();
    const { service, usersRepository, redisService } = makeService({
      messaging,
      cachedToken: 'cached-tok',
    });
    const ok = await service.sendToUser('u1', { title: 'T', body: 'B' });
    expect(ok).toBe(true);
    expect(redisService.getCachedFcmToken).toHaveBeenCalledWith('u1');
    expect(usersRepository.findOne).not.toHaveBeenCalled();
    expect(messaging.send.mock.calls[0][0].token).toBe('cached-tok');
  });

  it('returns false when neither Redis nor DB has a token', async () => {
    const messaging = okMessaging();
    const { service, usersRepository } = makeService({
      messaging,
      cachedToken: null,
      dbUser: { id: 'u1', fcmToken: null },
    });
    const ok = await service.sendToUser('u1', { title: 'T', body: 'B' });
    expect(ok).toBe(false);
    expect(usersRepository.findOne).toHaveBeenCalledWith({ where: { id: 'u1' } });
    expect(messaging.send).not.toHaveBeenCalled();
  });

  it('falls back to the DB token, re-caches it in Redis, and sends', async () => {
    const messaging = okMessaging();
    const { service, redisService } = makeService({
      messaging,
      cachedToken: null,
      dbUser: { id: 'u1', fcmToken: 'db-tok' },
    });
    const ok = await service.sendToUser('u1', { title: 'T', body: 'B' });
    expect(ok).toBe(true);
    expect(redisService.cacheFcmToken).toHaveBeenCalledWith('u1', 'db-tok');
    expect(messaging.send.mock.calls[0][0].token).toBe('db-tok');
  });

  it('survives a Redis read failure and falls through to the DB', async () => {
    const messaging = okMessaging();
    const { service, redisService } = makeService({
      messaging,
      dbUser: { id: 'u1', fcmToken: 'db-tok' },
    });
    redisService.getCachedFcmToken = jest.fn(async () => {
      throw new Error('redis down');
    });
    const ok = await service.sendToUser('u1', { title: 'T', body: 'B' });
    expect(ok).toBe(true);
    expect(messaging.send.mock.calls[0][0].token).toBe('db-tok');
  });
});

describe('NotificationsService.sendToUsers (multicast)', () => {
  it('returns early when messaging is not initialised', async () => {
    const { service, usersRepository } = makeService({ messaging: null });
    await service.sendToUsers(['u1'], { title: 'T', body: 'B' });
    expect(usersRepository.createQueryBuilder).not.toHaveBeenCalled();
  });

  it('returns early on an empty user list', async () => {
    const messaging = okMessaging();
    const { service, usersRepository } = makeService({ messaging });
    await service.sendToUsers([], { title: 'T', body: 'B' });
    expect(usersRepository.createQueryBuilder).not.toHaveBeenCalled();
  });

  it('does not call the multicast API when no user has a token', async () => {
    const messaging = okMessaging();
    const { service } = makeService({ messaging, qbRows: [] });
    await service.sendToUsers(['u1', 'u2'], { title: 'T', body: 'B' });
    expect(messaging.sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('sends a multicast to all collected tokens', async () => {
    const messaging = okMessaging();
    const { service } = makeService({
      messaging,
      qbRows: [{ fcmToken: 'a' }, { fcmToken: 'b' }],
    });
    await service.sendToUsers(['u1', 'u2'], {
      title: 'T',
      body: 'B',
      data: { type: 'broadcast' },
    });
    expect(messaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const arg = messaging.sendEachForMulticast.mock.calls[0][0];
    expect(arg.tokens).toEqual(['a', 'b']);
    expect(arg.data).toEqual({ type: 'broadcast' });
  });

  it('auto-clears tokens whose multicast response is a stale-token error', async () => {
    const messaging = okMessaging();
    messaging.sendEachForMulticast = jest.fn(async () => ({
      successCount: 1,
      responses: [
        { success: true },
        {
          success: false,
          error: { code: 'messaging/registration-token-not-registered' },
        },
      ],
    }));
    const { service, qb } = makeService({
      messaging,
      qbRows: [{ fcmToken: 'good' }, { fcmToken: 'stale' }],
    });
    await service.sendToUsers(['u1', 'u2'], { title: 'T', body: 'B' });
    // the stale (index 1) token triggered a clearStaleToken UPDATE
    expect(qb.update).toHaveBeenCalled();
    expect(qb.execute).toHaveBeenCalled();
  });

  it('swallows a multicast API failure without throwing', async () => {
    const messaging = okMessaging();
    messaging.sendEachForMulticast = jest.fn(async () => {
      throw new Error('fcm outage');
    });
    const { service } = makeService({ messaging, qbRows: [{ fcmToken: 'a' }] });
    await expect(
      service.sendToUsers(['u1'], { title: 'T', body: 'B' }),
    ).resolves.toBeUndefined();
  });
});

describe('NotificationsService.testPushToUser', () => {
  it('uses the Redis-cached token and reports success', async () => {
    const messaging = okMessaging();
    const { service } = makeService({ messaging, cachedToken: 'cached-abcdefghijklmnopqrstuvwxyz' });
    const res = await service.testPushToUser('u1');
    expect(res.success).toBe(true);
    expect(res.steps.some((s) => s.includes('Redis: token found'))).toBe(true);
    expect(messaging.send).toHaveBeenCalled();
  });

  it('returns user-not-found when Redis empty and DB has no such user', async () => {
    const messaging = okMessaging();
    const { service } = makeService({ messaging, cachedToken: null, dbUser: null });
    const res = await service.testPushToUser('ghost');
    expect(res.success).toBe(false);
    expect(res.message).toBe('User not found in database');
    expect(messaging.send).not.toHaveBeenCalled();
  });

  it('returns a helpful message when the user has a NULL token', async () => {
    const messaging = okMessaging();
    const { service } = makeService({
      messaging,
      cachedToken: null,
      dbUser: { id: 'u1', fcmToken: null },
    });
    const res = await service.testPushToUser('u1');
    expect(res.success).toBe(false);
    expect(res.message).toContain('No FCM token saved');
  });

  it('re-caches and succeeds when the token comes from the DB', async () => {
    const messaging = okMessaging();
    const { service, redisService } = makeService({
      messaging,
      cachedToken: null,
      dbUser: { id: 'u1', fcmToken: 'db-token-abcdefghijklmnopqrstuvwxyz' },
    });
    const res = await service.testPushToUser('u1');
    expect(res.success).toBe(true);
    expect(redisService.cacheFcmToken).toHaveBeenCalled();
  });

  it('captures the Firebase error code when the send fails', async () => {
    const messaging = okMessaging();
    messaging.send = jest.fn(async () => {
      throw { errorInfo: { code: 'messaging/invalid-argument', message: 'bad token' } };
    });
    const { service } = makeService({ messaging, cachedToken: 'cached-abcdefghijklmnopqrst' });
    const res = await service.testPushToUser('u1');
    expect(res.success).toBe(false);
    expect((res as any).firebaseErrorCode).toBe('messaging/invalid-argument');
    expect(res.message).toContain('messaging/invalid-argument');
  });
});

describe('NotificationsService notify* helpers', () => {
  function spyService() {
    const { service } = makeService({ messaging: okMessaging() });
    const spy = jest
      .spyOn(service, 'sendToUser')
      .mockResolvedValue(true);
    return { service, spy };
  }

  it('notifyWorkerNewBooking forwards skill + bookingId', async () => {
    const { service, spy } = spyService();
    await service.notifyWorkerNewBooking('w1', 'b9', 'Plumbing');
    expect(spy).toHaveBeenCalledWith(
      'w1',
      expect.objectContaining({
        title: 'New Job Request',
        body: 'A customer needs Plumbing help nearby.',
        data: { type: 'new_booking', bookingId: 'b9' },
      }),
    );
  });

  it('notifyCustomerBookingAccepted names the worker', async () => {
    const { service, spy } = spyService();
    await service.notifyCustomerBookingAccepted('c1', 'Anu');
    expect(spy).toHaveBeenCalledWith(
      'c1',
      expect.objectContaining({
        body: 'Anu is on the way to your location.',
        data: { type: 'booking_accepted' },
      }),
    );
  });

  it('notifyCustomerWorkerArrived carries the arrival OTP in body + data', async () => {
    const { service, spy } = spyService();
    await service.notifyCustomerWorkerArrived('c1', '4821');
    const payload = spy.mock.calls[0][1];
    expect(payload.body).toContain('4821');
    expect(payload.data).toEqual({ type: 'worker_arrived', otp: '4821' });
  });

  it('notifyCustomerJobComplete carries the completion OTP', async () => {
    const { service, spy } = spyService();
    await service.notifyCustomerJobComplete('c1', '9090');
    const payload = spy.mock.calls[0][1];
    expect(payload.body).toContain('9090');
    expect(payload.data).toEqual({ type: 'job_complete', otp: '9090' });
  });

  it('notifyBookingCancelled uses the supplied reason', async () => {
    const { service, spy } = spyService();
    await service.notifyBookingCancelled('u1', 'Worker unavailable');
    expect(spy.mock.calls[0][1].body).toBe('Worker unavailable');
  });

  it('notifyBookingCancelled falls back to a default reason', async () => {
    const { service, spy } = spyService();
    await service.notifyBookingCancelled('u1');
    expect(spy.mock.calls[0][1].body).toBe('Your booking has been cancelled.');
  });

  it('notifyGpsStrike stringifies the strike count in data', async () => {
    const { service, spy } = spyService();
    await service.notifyGpsStrike('w1', 2);
    const payload = spy.mock.calls[0][1];
    expect(payload.body).toContain('Strike 2/3');
    expect(payload.data).toEqual({ type: 'gps_strike', strike: '2' });
  });
});
