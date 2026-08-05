import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ConfigService } from '@nestjs/config';
import { createHmac, randomUUID } from 'crypto';
import { Booking, BookingStatus } from '../bookings/booking.entity';
import { RedisService } from '../redis/redis.service';

const CALLABLE_STATUSES = new Set<BookingStatus>([
  BookingStatus.ACCEPTED,
  BookingStatus.CONFIRMED,
  BookingStatus.ARRIVED,
  BookingStatus.ACTIVE,
]);

export type VoiceCallRole = 'customer' | 'operator';

export interface VoiceCallSession {
  callId: string;
  bookingId: string;
  callerId: string;
  calleeId: string;
  status: 'ringing' | 'active';
  createdAt: string;
}

@Injectable()
export class VoiceCallsService {
  constructor(
    @InjectRepository(Booking)
    private readonly bookingsRepo: Repository<Booking>,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
  ) {}

  private sessionKey(bookingId: string) {
    return `voice_call:booking:${bookingId}`;
  }

  /** ICE servers for flutter_webrtc (STUN always; TURN when env configured). */
  getIceServers(): {
    iceServers: Array<{
      urls: string | string[];
      username?: string;
      credential?: string;
    }>;
  } {
    const stunRaw =
      this.config.get<string>('WEBRTC_STUN_URLS') ||
      'stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302';
    const stunUrls = stunRaw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);

    const iceServers: Array<{
      urls: string | string[];
      username?: string;
      credential?: string;
    }> = [{ urls: stunUrls.length === 1 ? stunUrls[0] : stunUrls }];

    const turnUrlsRaw = this.config.get<string>('WEBRTC_TURN_URLS')?.trim();
    if (turnUrlsRaw) {
      const turnUrls = turnUrlsRaw
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
      const secret = this.config.get<string>('WEBRTC_TURN_SECRET')?.trim();
      const staticUser = this.config.get<string>('WEBRTC_TURN_USERNAME')?.trim();
      const staticPass = this.config
        .get<string>('WEBRTC_TURN_CREDENTIAL')
        ?.trim();

      if (secret) {
        // coturn time-limited credentials (shared secret)
        const ttl = Number(
          this.config.get<string>('WEBRTC_TURN_TTL_SECONDS') || '86400',
        );
        const expiry = Math.floor(Date.now() / 1000) + (ttl > 0 ? ttl : 86400);
        const username = `${expiry}:gixbee`;
        const credential = createHmac('sha1', secret)
          .update(username)
          .digest('base64');
        iceServers.push({
          urls: turnUrls.length === 1 ? turnUrls[0] : turnUrls,
          username,
          credential,
        });
      } else if (staticUser && staticPass) {
        iceServers.push({
          urls: turnUrls.length === 1 ? turnUrls[0] : turnUrls,
          username: staticUser,
          credential: staticPass,
        });
      }
    }

    return { iceServers };
  }

  async assertCallableParticipant(
    bookingId: string,
    userId: string,
  ): Promise<{ booking: Booking; role: VoiceCallRole; peerId: string }> {
    const booking = await this.bookingsRepo.findOne({
      where: { id: bookingId },
      relations: { customer: true, operator: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');

    let role: VoiceCallRole | null = null;
    if (booking.customer?.id === userId) role = 'customer';
    else if (booking.operator?.id === userId) role = 'operator';
    if (!role) {
      throw new BadRequestException(
        'You are not a participant of this booking',
      );
    }

    if (!CALLABLE_STATUSES.has(booking.status)) {
      throw new BadRequestException(
        'Voice calls are only available while the job is in progress',
      );
    }

    const peerId =
      role === 'customer' ? booking.operator?.id : booking.customer?.id;
    if (!peerId) {
      throw new BadRequestException('No counterpart assigned for this booking');
    }

    return { booking, role, peerId };
  }

  async getActiveSession(bookingId: string): Promise<VoiceCallSession | null> {
    const raw = await this.redis.get(this.sessionKey(bookingId));
    if (!raw) return null;
    try {
      return JSON.parse(raw) as VoiceCallSession;
    } catch {
      return null;
    }
  }

  async startRinging(opts: {
    bookingId: string;
    callerId: string;
    calleeId: string;
  }): Promise<VoiceCallSession> {
    const existing = await this.getActiveSession(opts.bookingId);
    if (existing) {
      throw new BadRequestException('A call is already in progress for this booking');
    }
    const session: VoiceCallSession = {
      callId: randomUUID(),
      bookingId: opts.bookingId,
      callerId: opts.callerId,
      calleeId: opts.calleeId,
      status: 'ringing',
      createdAt: new Date().toISOString(),
    };
    await this.redis.set(
      this.sessionKey(opts.bookingId),
      JSON.stringify(session),
      120, // ring timeout
    );
    return session;
  }

  async markActive(bookingId: string, userId: string): Promise<VoiceCallSession> {
    const session = await this.getActiveSession(bookingId);
    if (!session) throw new BadRequestException('No ringing call to accept');
    if (session.calleeId !== userId) {
      throw new BadRequestException('Only the callee can accept this call');
    }
    session.status = 'active';
    await this.redis.set(
      this.sessionKey(bookingId),
      JSON.stringify(session),
      60 * 60,
    );
    return session;
  }

  async clearSession(bookingId: string): Promise<VoiceCallSession | null> {
    const session = await this.getActiveSession(bookingId);
    await this.redis.del(this.sessionKey(bookingId));
    return session;
  }

  async assertSignalParticipant(
    bookingId: string,
    userId: string,
  ): Promise<VoiceCallSession> {
    const session = await this.getActiveSession(bookingId);
    if (!session) throw new BadRequestException('No active call for this booking');
    if (session.callerId !== userId && session.calleeId !== userId) {
      throw new BadRequestException('Not a participant of this call');
    }
    return session;
  }
}
