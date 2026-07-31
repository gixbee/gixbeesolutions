import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { WsJwtGuard } from './ws-jwt.guard';

/**
 * Unit tests for the Socket.IO JWT adapter. We assert getRequest() surfaces
 * handshake.auth.token as Authorization on the socket itself (so passport can
 * attach `.user`), and handleRequest() stores the validated user on
 * client.data.user for gateway handlers.
 */

function makeClient(handshake: Record<string, unknown>) {
  return {
    handshake,
    headers: {} as Record<string, unknown>,
    data: {} as Record<string, unknown>,
    user: undefined as unknown,
  };
}

function ctxWithClient(client: ReturnType<typeof makeClient>): ExecutionContext {
  return {
    switchToWs: () => ({
      getClient: () => client,
    }),
  } as any;
}

function ctxWith(handshake: Record<string, unknown>): ExecutionContext {
  return ctxWithClient(makeClient(handshake));
}

describe('WsJwtGuard.getRequest', () => {
  const guard = new WsJwtGuard();

  it('maps handshake.auth.token into a Bearer Authorization header on the socket', () => {
    const req = guard.getRequest(
      ctxWith({ auth: { token: 'abc.def.ghi' }, headers: {} }),
    );
    expect(req.headers.authorization).toBe('Bearer abc.def.ghi');
  });

  it('returns the socket client (not a throwaway headers object)', () => {
    const client = makeClient({ auth: { token: 't' }, headers: {} });
    const req = guard.getRequest(ctxWithClient(client));
    expect(req).toBe(client);
  });

  it('keeps an already-prefixed Bearer token from auth', () => {
    const req = guard.getRequest(
      ctxWith({ auth: { token: 'Bearer already' }, headers: {} }),
    );
    expect(req.headers.authorization).toBe('Bearer already');
  });

  it('falls back to handshake.headers.authorization', () => {
    const req = guard.getRequest(
      ctxWith({
        auth: {},
        headers: { authorization: 'Bearer from-header' },
      }),
    );
    expect(req.headers.authorization).toBe('Bearer from-header');
  });

  it('returns undefined authorization when no token is present', () => {
    const req = guard.getRequest(ctxWith({ auth: {}, headers: {} }));
    expect(req.headers.authorization).toBeUndefined();
  });
});

describe('WsJwtGuard.handleRequest', () => {
  const guard = new WsJwtGuard();

  it('stores the validated user on client.data.user and client.user', () => {
    const client = makeClient({ auth: {}, headers: {} });
    const user = { userId: 'u-1', role: 'CUSTOMER' };
    const result = guard.handleRequest(
      null,
      user,
      null,
      ctxWithClient(client),
    );
    expect(result).toBe(user);
    expect(client.data.user).toBe(user);
    expect(client.user).toBe(user);
  });

  it('throws UnauthorizedException when user is missing', () => {
    const client = makeClient({ auth: {}, headers: {} });
    expect(() =>
      guard.handleRequest(null, null, { message: 'jwt expired' }, ctxWithClient(client)),
    ).toThrow(UnauthorizedException);
  });
});
