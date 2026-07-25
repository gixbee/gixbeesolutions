import { ExecutionContext } from '@nestjs/common';
import { WsJwtGuard } from './ws-jwt.guard';

/**
 * Unit tests for the Socket.IO JWT adapter. We only assert getRequest() — the
 * passport validate path is covered by JwtStrategy specs. The bug this guard
 * fixes is that handshake.auth.token was never surfaced as Authorization.
 */

function ctxWith(handshake: Record<string, unknown>): ExecutionContext {
  return {
    switchToWs: () => ({
      getClient: () => ({ handshake }),
    }),
  } as any;
}

describe('WsJwtGuard.getRequest', () => {
  const guard = new WsJwtGuard();

  it('maps handshake.auth.token into a Bearer Authorization header', () => {
    const req = guard.getRequest(
      ctxWith({ auth: { token: 'abc.def.ghi' }, headers: {} }),
    );
    expect(req.headers.authorization).toBe('Bearer abc.def.ghi');
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
