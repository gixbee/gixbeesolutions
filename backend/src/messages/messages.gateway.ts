import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  ConnectedSocket,
  WsException,
} from '@nestjs/websockets';
import { UseGuards } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { WsJwtGuard } from '../auth/ws-jwt.guard';

/**
 * Realtime chat delivery. Shares the same Socket.IO server as WorkerGateway
 * (Nest injects the one underlying server into every gateway), so clients
 * connect once and receive both job and chat events.
 *
 * Clients call `joinUserRoom` after connecting; messages are then pushed to
 * `user_<recipientId>` as `new_message`.
 */
@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
@UseGuards(WsJwtGuard)
export class MessagesGateway {
  @WebSocketServer()
  server: Server;

  @SubscribeMessage('joinUserRoom')
  handleJoinUserRoom(@ConnectedSocket() client: Socket) {
    const user =
      (client as any).data?.user ?? (client as any).user ?? undefined;
    const userId = user?.userId;
    if (typeof userId !== 'string' || userId.length === 0) {
      throw new WsException('Unauthorized');
    }

    // The personal room always comes from the verified JWT. A body userId is
    // intentionally ignored so a client cannot subscribe to another account.
    client.join(`user_${userId}`);
    return { event: 'joinedUserRoom', data: userId };
  }

  /** Push a message payload to the recipient's personal room. */
  emitToUser(userId: string, payload: Record<string, unknown>) {
    this.server?.to(`user_${userId}`).emit('new_message', payload);
  }

  /** Push a named booking/job event to `user_<userId>` (FCM companion). */
  emitUserEvent(
    userId: string,
    event: string,
    payload: Record<string, unknown>,
  ) {
    if (!userId || !event) return;
    this.server?.to(`user_${userId}`).emit(event, payload);
  }
}
