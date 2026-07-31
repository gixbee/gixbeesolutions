import {
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
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
 * can validate the same Bearer token the REST API uses, then stores the
 * validated user on `client.data.user` / `client.user` so handlers can trust
 * JWT identity (never a client-supplied body userId).
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

    // Return the socket itself so passport attaches `.user` onto it (not onto
    // a throwaway { headers } object that handlers can never see).
    client.headers = {
      ...(client.headers ?? {}),
      authorization: bearer,
    };
    return client;
  }

  handleRequest<TUser = any>(
    err: any,
    user: TUser,
    info: any,
    context: ExecutionContext,
  ): TUser {
    if (err || !user) {
      throw err || new UnauthorizedException(info?.message || 'Unauthorized');
    }
    const client = context.switchToWs().getClient();
    if (client) {
      client.data = client.data ?? {};
      client.data.user = user;
      client.user = user;
    }
    return user;
  }
}
