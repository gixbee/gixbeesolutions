import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  MessageBody,
  ConnectedSocket,
  WsException,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { UseGuards } from '@nestjs/common';
import { WsJwtGuard } from '../auth/ws-jwt.guard';
import { RedisService } from '../redis/redis.service';

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
// Must use WsJwtGuard — Flutter sends JWT via socket.auth.token, not HTTP
// Authorization. JwtAuthGuard silently blocked joinJobRoom + updateLocation.
@UseGuards(WsJwtGuard)
export class WorkerGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  constructor(private readonly redisService: RedisService) {}

  handleConnection(client: Socket) {
    console.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    console.log(`Client disconnected: ${client.id}`);
  }

  /** JWT identity from WsJwtGuard — never trust a body/userId field. */
  private authedUserId(client: Socket): string {
    const user =
      (client as any).data?.user ?? (client as any).user ?? undefined;
    const userId = user?.userId;
    if (typeof userId !== 'string' || userId.length === 0) {
      throw new WsException('Unauthorized');
    }
    return userId;
  }

  @SubscribeMessage('updateLocation')
  async handleLocationUpdate(
    @MessageBody()
    data: { userId?: string; lat: number; lng: number; jobId?: string },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = this.authedUserId(client);
    if (typeof data?.lat !== 'number' || typeof data?.lng !== 'number') {
      throw new WsException('Invalid location');
    }

    // 1. Persist to Redis so the background health-check (10-minute rule) can see it
    await this.redisService.updateWorkerLocation(userId, data.lat, data.lng);

    // 2. If a jobId is provided, only broadcast to that job's room
    const payload = {
      userId,
      lat: data.lat,
      lng: data.lng,
      timestamp: new Date().toISOString(),
    };
    if (data.jobId) {
      this.server.to(`job_${data.jobId}`).emit('locationUpdated', payload);
    } else {
      // Fallback: emit only back to the sender
      client.emit('locationUpdated', payload);
    }
  }

  @SubscribeMessage('joinJobRoom')
  handleJoinJobRoom(
    @MessageBody() data: { jobId: string },
    @ConnectedSocket() client: Socket,
  ) {
    client.join(`job_${data.jobId}`);
    return { event: 'joined', data: `Joined room job_${data.jobId}` };
  }

  @SubscribeMessage('leaveJobRoom')
  handleLeaveJobRoom(
    @MessageBody() data: { jobId: string },
    @ConnectedSocket() client: Socket,
  ) {
    if (data?.jobId) {
      client.leave(`job_${data.jobId}`);
    }
    return {
      event: 'left',
      data: data?.jobId ? `Left room job_${data.jobId}` : null,
    };
  }
}
