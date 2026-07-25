import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';

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
export class MessagesGateway {
  @WebSocketServer()
  server: Server;

  @SubscribeMessage('joinUserRoom')
  handleJoinUserRoom(
    @MessageBody() data: { userId: string },
    @ConnectedSocket() client: Socket,
  ) {
    if (data?.userId) {
      client.join(`user_${data.userId}`);
    }
    return { event: 'joinedUserRoom', data: data?.userId };
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
