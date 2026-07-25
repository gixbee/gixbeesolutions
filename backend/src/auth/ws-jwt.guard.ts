import { ExecutionContext, Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/**
 * Socket.IO JWT guard.
 *
 * The Flutter client authenticates with `socket.auth = { token }` (see
 * SocketService.connect), not an HTTP `Authorization` header. The default
 * JwtAuthGuard / ExtractJwt.fromAuthHeaderAsBearerToken() therefore rejects
 * every WorkerGateway handler (joinJobRoom, updateLocation) — which is why
 * customers never receive live worker GPS on the tracking map.
 *
 * This guard adapts the handshake into a request-shaped object so passport-jwt
 * can validate the same Bearer token the REST API uses.
 */
@Injectable()
export class WsJwtGuard extends AuthGuard('jwt') {
  getRequest(context: ExecutionContext) {
    const client = context.switchToWs().getClient();
    const handshake = client?.handshake ?? {};
    const authToken =
      handshake.auth?.token ??
      handshake.auth?.Authorization ??
      handshake.auth?.authorization;
    const headerAuth =
      typeof handshake.headers?.authorization === 'string'
        ? handshake.headers.authorization
        : typeof handshake.headers?.Authorization === 'string'
          ? handshake.headers.Authorization
          : undefined;

    let bearer: string | undefined;
    if (typeof authToken === 'string' && authToken.length > 0) {
      bearer = authToken.startsWith('Bearer ')
        ? authToken
        : `Bearer ${authToken}`;
    } else if (headerAuth) {
      bearer = headerAuth.startsWith('Bearer ')
        ? headerAuth
        : `Bearer ${headerAuth}`;
    }

    return {
      headers: {
        authorization: bearer,
      },
    };
  }
}
