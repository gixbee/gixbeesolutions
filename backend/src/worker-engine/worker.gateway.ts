import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  OnGatewayConnection,
  OnGatewayDisconnect,
  MessageBody,
  ConnectedSocket,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RedisService } from '../redis/redis.service';

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
@UseGuards(JwtAuthGuard)
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

  @SubscribeMessage('updateLocation')
  async handleLocationUpdate(
    @MessageBody() data: { userId: string; lat: number; lng: number; jobId?: string },
    @ConnectedSocket() client: Socket,
  ) {
    // 1. Persist to Redis so the background health-check (10-minute rule) can see it
    await this.redisService.updateWorkerLocation(data.userId, data.lat, data.lng);

    // 2. If a jobId is provided, only broadcast to that job's room
    if (data.jobId) {
      this.server.to(`job_${data.jobId}`).emit('locationUpdated', {
        userId: data.userId,
        lat: data.lat,
        lng: data.lng,
        timestamp: new Date().toISOString(),
      });
    } else {
      // Fallback: emit only back to the sender
      client.emit('locationUpdated', {
        userId: data.userId,
        lat: data.lat,
        lng: data.lng,
        timestamp: new Date().toISOString(),
      });
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
}
