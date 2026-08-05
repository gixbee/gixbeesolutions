import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
  WsException,
} from '@nestjs/websockets';
import { UseGuards, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { WsJwtGuard } from '../auth/ws-jwt.guard';
import { VoiceCallsService } from './voice-calls.service';
import { NotificationsService } from '../notifications/notifications.service';

@WebSocketGateway({
  cors: { origin: '*' },
})
@UseGuards(WsJwtGuard)
export class VoiceCallsGateway {
  private readonly logger = new Logger(VoiceCallsGateway.name);

  @WebSocketServer()
  server: Server;

  constructor(
    private readonly voiceCalls: VoiceCallsService,
    private readonly notifications: NotificationsService,
  ) {}

  private authedUserId(client: Socket): string {
    const user =
      (client as any).data?.user ?? (client as any).user ?? undefined;
    const userId = user?.userId;
    if (typeof userId !== 'string' || userId.length === 0) {
      throw new WsException('Unauthorized');
    }
    return userId;
  }

  /**
   * Socket.IO only invokes the client ack when the handler RETURNS. A thrown
   * WsException emits an `exception` event instead, so the Flutter caller sat
   * on `emitWithAck` until its timeout and showed "Calling…" forever with no
   * reason. Every handler therefore resolves to `{ ok: false, error }`.
   */
  private fail(scope: string, e: unknown) {
    const error = (e as Error)?.message || `${scope} failed`;
    this.logger.warn(`${scope}: ${error}`);
    return { ok: false as const, error };
  }

  private emitToUser(
    userId: string,
    event: string,
    payload: Record<string, unknown>,
  ) {
    this.server?.to(`user_${userId}`).emit(event, payload);
  }

  /**
   * Live sockets in the callee's personal room, counted across BOTH replicas
   * (fetchSockets() goes through the Redis adapter).
   *
   * Emitting into an empty room succeeds silently, so an offline callee was
   * indistinguishable from a broken call: the caller sat on "Calling…" for the
   * whole ring window and then reported a generic connection error. Returns -1
   * when the lookup itself fails, so an adapter hiccup never blocks a call —
   * only a definite 0 does.
   */
  private async liveSocketCount(userId: string): Promise<number> {
    try {
      const sockets = await this.server.in(`user_${userId}`).fetchSockets();
      return sockets.length;
    } catch (e) {
      this.logger.warn(
        `room lookup failed for user_${userId}: ${(e as Error)?.message}`,
      );
      return -1;
    }
  }

  @SubscribeMessage('voice_call_invite')
  async handleInvite(
    @MessageBody()
    data: { bookingId?: string; callerName?: string },
    @ConnectedSocket() client: Socket,
  ) {
    const callerId = this.authedUserId(client);
    const bookingId = data?.bookingId;
    if (!bookingId) return this.fail('voice_call_invite', 'bookingId required');

    try {
      const { booking, peerId } =
        await this.voiceCalls.assertCallableParticipant(bookingId, callerId);

      const callerName =
        (typeof data?.callerName === 'string' && data.callerName.trim()) ||
        'Gixbee user';
      const skill = booking.skill || 'your booking';

      // No live socket means nobody can answer. Reserving a ringing session
      // here would also hold the Redis key for its full TTL and make the next
      // retry look "already in progress", so bail out before startRinging.
      const reachable = await this.liveSocketCount(peerId);
      if (reachable === 0) {
        this.logger.warn(
          `invite booking=${bookingId} ${callerId} -> ${peerId} refused: callee has no live socket`,
        );
        this.notifications
          .sendToUser(peerId, {
            title: 'Missed call',
            body: `${callerName} tried to call you about ${skill}`,
            data: { type: 'voice_call_missed', bookingId, callerId, callerName },
          })
          .catch((e) =>
            this.logger.warn(
              `missed-call FCM failed: ${(e as Error)?.message}`,
            ),
          );
        return {
          ok: false as const,
          error:
            'They are not online right now. We sent them a notification — try again in a moment.',
        };
      }

      const session = await this.voiceCalls.startRinging({
        bookingId,
        callerId,
        calleeId: peerId,
      });

      const payload = {
        callId: session.callId,
        bookingId,
        callerId,
        calleeId: peerId,
        callerName,
        skill,
      };

      this.logger.log(
        `invite call=${session.callId} booking=${bookingId} ${callerId} -> ${peerId} calleeSockets=${reachable}`,
      );
      this.emitToUser(peerId, 'voice_call_invite', payload);

      // Wake callee if backgrounded — no phone numbers in data.
      this.notifications
        .sendToUser(peerId, {
          title: 'Incoming call',
          body: `${callerName} is calling about ${skill}`,
          data: {
            type: 'voice_call',
            bookingId,
            callId: session.callId,
            callerId,
            callerName,
          },
        })
        .catch((e) =>
          this.logger.warn(`voice_call FCM failed: ${(e as Error)?.message}`),
        );

      return { ok: true, ...payload };
    } catch (e) {
      return this.fail('voice_call_invite', e);
    }
  }

  @SubscribeMessage('voice_call_accept')
  async handleAccept(
    @MessageBody() data: { bookingId?: string; callId?: string },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = this.authedUserId(client);
    const bookingId = data?.bookingId;
    if (!bookingId) return this.fail('voice_call_accept', 'bookingId required');

    try {
      const session = await this.voiceCalls.markActive(bookingId, userId);
      if (data?.callId && data.callId !== session.callId) {
        return this.fail('voice_call_accept', 'Stale call id');
      }
      const payload = {
        callId: session.callId,
        bookingId,
        callerId: session.callerId,
        calleeId: session.calleeId,
      };
      this.logger.log(
        `accept call=${session.callId} booking=${bookingId} by=${userId}`,
      );
      this.emitToUser(session.callerId, 'voice_call_accept', payload);
      return { ok: true, ...payload };
    } catch (e) {
      return this.fail('voice_call_accept', e);
    }
  }

  @SubscribeMessage('voice_call_reject')
  async handleReject(
    @MessageBody() data: { bookingId?: string; callId?: string },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = this.authedUserId(client);
    const bookingId = data?.bookingId;
    if (!bookingId) return this.fail('voice_call_reject', 'bookingId required');

    try {
      const session = await this.voiceCalls.getActiveSession(bookingId);
      if (!session) return { ok: true };
      if (session.calleeId !== userId && session.callerId !== userId) {
        return this.fail('voice_call_reject', 'Not a call participant');
      }
      await this.voiceCalls.clearSession(bookingId);
      const peerId =
        userId === session.callerId ? session.calleeId : session.callerId;
      this.emitToUser(peerId, 'voice_call_reject', {
        callId: session.callId,
        bookingId,
        by: userId,
      });
      return { ok: true };
    } catch (e) {
      return this.fail('voice_call_reject', e);
    }
  }

  @SubscribeMessage('voice_call_hangup')
  async handleHangup(
    @MessageBody() data: { bookingId?: string; callId?: string },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = this.authedUserId(client);
    const bookingId = data?.bookingId;
    if (!bookingId) return this.fail('voice_call_hangup', 'bookingId required');

    try {
      const session = await this.voiceCalls.clearSession(bookingId);
      if (session) {
        const peerId =
          userId === session.callerId ? session.calleeId : session.callerId;
        this.emitToUser(peerId, 'voice_call_hangup', {
          callId: session.callId,
          bookingId,
          by: userId,
        });
      }
      return { ok: true };
    } catch (e) {
      return this.fail('voice_call_hangup', e);
    }
  }

  /** SDP / ICE trickle between peers. */
  @SubscribeMessage('voice_call_signal')
  async handleSignal(
    @MessageBody()
    data: {
      bookingId?: string;
      callId?: string;
      signal?: Record<string, unknown>;
    },
    @ConnectedSocket() client: Socket,
  ) {
    const userId = this.authedUserId(client);
    const bookingId = data?.bookingId;
    if (!bookingId || !data?.signal) {
      return this.fail('voice_call_signal', 'bookingId and signal required');
    }

    try {
      const session = await this.voiceCalls.assertSignalParticipant(
        bookingId,
        userId,
      );
      if (data.callId && data.callId !== session.callId) {
        return this.fail('voice_call_signal', 'Stale call id');
      }
      const peerId =
        userId === session.callerId ? session.calleeId : session.callerId;
      // Offer/answer only — candidate trickle would flood the log.
      const signalType = String(data.signal.type ?? '');
      if (signalType === 'offer' || signalType === 'answer') {
        this.logger.log(
          `signal ${signalType} call=${session.callId} ${userId} -> ${peerId}`,
        );
      }
      this.emitToUser(peerId, 'voice_call_signal', {
        callId: session.callId,
        bookingId,
        from: userId,
        signal: data.signal,
      });
      return { ok: true };
    } catch (e) {
      return this.fail('voice_call_signal', e);
    }
  }
}
