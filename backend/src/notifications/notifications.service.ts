import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as admin from 'firebase-admin';
import { User } from '../users/user.entity';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class NotificationsService implements OnModuleInit {
  private readonly logger = new Logger(NotificationsService.name);
  private messaging: admin.messaging.Messaging | null = null;

  constructor(
    private readonly configService: ConfigService,
    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
    private readonly redisService: RedisService,
  ) {}

  // ── Firebase Admin SDK Init ───────────────────────────────────────────────

  onModuleInit() {
    if (!admin.apps.length) {
      // Strategy 1: Use JSON key file (most reliable)
      const keyFilePath = this.configService.get<string>('FIREBASE_KEY_PATH');
      const googleAppCreds = process.env.GOOGLE_APPLICATION_CREDENTIALS;

      if (keyFilePath || googleAppCreds) {
        const filePath = keyFilePath || googleAppCreds;
        try {
          // eslint-disable-next-line @typescript-eslint/no-var-requires
          const serviceAccount = require(filePath!);
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
          });
          this.logger.log(`Firebase Admin SDK initialized from JSON file: ${filePath}`);
        } catch (e) {
          this.logger.error(`Failed to load Firebase key file at ${filePath}: ${e}`);
          return;
        }
      } else {
        // Strategy 2: Fall back to individual .env variables
        const projectId = this.configService.get<string>('FIREBASE_PROJECT_ID');
        const clientEmail = this.configService.get<string>('FIREBASE_CLIENT_EMAIL');
        const privateKey = this.configService
          .get<string>('FIREBASE_PRIVATE_KEY')
          ?.replace(/\\n/g, '\n');

        if (!projectId || !clientEmail || !privateKey) {
          this.logger.warn(
            'Firebase credentials missing — push notifications disabled. ' +
              'Set FIREBASE_KEY_PATH to a JSON key file, or set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY in .env',
          );
          return;
        }

        admin.initializeApp({
          credential: admin.credential.cert({ projectId, clientEmail, privateKey }),
        });
        this.logger.log('Firebase Admin SDK initialized from .env variables');
      }
    }

    this.messaging = admin.messaging();
    this.logger.log('Firebase Admin SDK ready — push notifications enabled');
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  getDiagnostics() {
    const projectId = this.configService.get<string>('FIREBASE_PROJECT_ID');
    const clientEmail = this.configService.get<string>('FIREBASE_CLIENT_EMAIL');
    const privateKey = this.configService.get<string>('FIREBASE_PRIVATE_KEY');

    return {
      firebaseInitialized: !!this.messaging,
      credentials: {
        hasProjectId: !!projectId,
        hasClientEmail: !!clientEmail,
        hasPrivateKey: !!privateKey,
        projectId: projectId ?? '(not set)',
      },
      firebaseAppsCount: admin.apps.length,
    };
  }

  // ── Core: send to a single FCM token ─────────────────────────────────────

  /**
   * Send a push notification directly to a device by its FCM token.
   * Supports both notification+data and data-only FCM messages.
   * FCM requires all data values to be strings.
   */
  async sendToDevice(payload: {
    fcmToken: string;
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<boolean> {
    if (!this.messaging) {
      this.logger.warn('[FCM] Firebase not initialized — skipping push');
      return false;
    }

    try {
      const messageId = await this.messaging.send({
        token: payload.fcmToken,
        notification: {
          title: payload.title,
          body: payload.body,
        },
        data: payload.data ?? {},
        android: {
          priority: 'high',
          notification: {
            channelId: 'gixbee_high_importance',
            sound: 'default',
            priority: 'max',
            defaultSound: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
              contentAvailable: true,
            },
          },
          headers: { 'apns-priority': '10' },
        },
      });

      this.logger.log(`[FCM] Push sent — messageId: ${messageId}`);
      return true;
    } catch (error: any) {
      const code = error?.errorInfo?.code ?? '';

      // Token no longer valid — clean it up so we don't retry with it
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        this.logger.warn(
          `[FCM] Stale token — clearing from DB: ${payload.fcmToken.substring(0, 20)}...`,
        );
        await this.clearStaleToken(payload.fcmToken);
      } else {
        this.logger.error('[FCM] Failed to send push', error?.message ?? error);
      }
      return false;
    }
  }

  // ── Core: send to a user by their database ID ─────────────────────────────

  /**
   * Look up a user's FCM token (Redis first, then DB) and send a push.
   *
   * Full chain:
   *   Flutter gets FCM token (firebase_messaging.getToken())
   *   → registers via PATCH /auth/fcm-token
   *   → stored in user.fcmToken (DB) + cached in Redis under user:fcm:{userId}
   *   → NotificationsService.sendToUser(userId) reads Redis/DB
   *   → sendToDevice(fcmToken) → Firebase Admin SDK → FCM → Flutter device
   */
  async sendToUser(
    userId: string,
    payload: {
      title: string;
      body: string;
      data?: Record<string, string>;
    },
  ): Promise<boolean> {
    // 1. Fast path — Redis cache (avoids DB query per notification)
    const cachedToken = await this.redisService
      .getCachedFcmToken(userId)   // ← matches redis.service.ts method name
      .catch(() => null);

    if (cachedToken) {
      return this.sendToDevice({ fcmToken: cachedToken, ...payload });
    }

    // 2. Cache miss — fall back to DB
    const user = await this.usersRepository.findOne({ where: { id: userId } });

    if (!user?.fcmToken) {
      this.logger.warn(
        `[FCM] No FCM token for user ${userId} — not registered or token cleared`,
      );
      return false;
    }

    // 3. Re-populate Redis for next time
    await this.redisService.cacheFcmToken(userId, user.fcmToken).catch(() => {});

    return this.sendToDevice({ fcmToken: user.fcmToken, ...payload });
  }

  // ── Test Push with diagnostics ────────────────────────────────────────────

  async testPushToUser(userId: string) {
    const steps: string[] = [];
    let fcmToken: string | null = null;

    // Step 1: Check Redis
    try {
      const cachedToken = await this.redisService.getCachedFcmToken(userId);
      if (cachedToken) {
        fcmToken = cachedToken;
        steps.push(`✅ Redis: token found (${cachedToken.substring(0, 20)}...)`);
      } else {
        steps.push('⚠️ Redis: no cached token');
      }
    } catch (e) {
      steps.push(`❌ Redis error: ${e}`);
    }

    // Step 2: Check DB
    if (!fcmToken) {
      try {
        const user = await this.usersRepository.findOne({ where: { id: userId } });
        if (!user) {
          steps.push('❌ DB: user not found');
          return { success: false, userId, steps, message: 'User not found in database' };
        }
        if (user.fcmToken) {
          fcmToken = user.fcmToken;
          steps.push(`✅ DB: token found (${user.fcmToken.substring(0, 20)}...)`);
          // Re-cache
          await this.redisService.cacheFcmToken(userId, user.fcmToken).catch(() => {});
        } else {
          steps.push('❌ DB: user.fcmToken is NULL — device never registered');
          return {
            success: false,
            userId,
            steps,
            message: 'No FCM token saved for this user. The app needs to call PATCH /auth/fcm-token after login.',
          };
        }
      } catch (e) {
        steps.push(`❌ DB error: ${e}`);
        return { success: false, userId, steps, message: `DB lookup failed: ${e}` };
      }
    }

    // Step 3: Send push directly (with full error capture)
    steps.push('📤 Sending test push via Firebase Admin SDK...');
    steps.push(`📋 Token length: ${fcmToken!.length} chars`);

    try {
      const messageId = await this.messaging!.send({
        token: fcmToken!,
        notification: {
          title: '🔔 FCM Test',
          body: 'If you see this, push notifications are working!',
        },
        data: { type: 'test_push' },
        android: {
          priority: 'high',
          notification: {
            channelId: 'gixbee_high_importance',
            sound: 'default',
            priority: 'max',
          },
        },
      });

      steps.push(`✅ Firebase accepted — messageId: ${messageId}`);
      return {
        success: true,
        userId,
        fcmTokenPrefix: fcmToken?.substring(0, 30) + '...',
        steps,
        message: 'Push sent successfully! You should see a notification.',
      };
    } catch (error: any) {
      const code = error?.errorInfo?.code ?? 'unknown';
      const msg = error?.errorInfo?.message ?? error?.message ?? String(error);
      steps.push(`❌ Firebase error code: ${code}`);
      steps.push(`❌ Firebase error msg: ${msg}`);

      return {
        success: false,
        userId,
        fcmTokenPrefix: fcmToken?.substring(0, 30) + '...',
        firebaseErrorCode: code,
        steps,
        message: `Firebase error: ${code} — ${msg}`,
      };
    }
  }

  // ── Multicast: send to multiple users ─────────────────────────────────────

  async sendToUsers(
    userIds: string[],
    payload: { title: string; body: string; data?: Record<string, string> },
  ): Promise<void> {
    if (!this.messaging || userIds.length === 0) return;

    const users = await this.usersRepository
      .createQueryBuilder('user')
      .select(['user.id', 'user.fcmToken'])
      .where('user.id IN (:...ids)', { ids: userIds })
      .andWhere('user.fcmToken IS NOT NULL')
      .getMany();

    const tokens = users.map((u) => u.fcmToken).filter(Boolean) as string[];
    if (tokens.length === 0) return;

    try {
      const response = await this.messaging.sendEachForMulticast({
        tokens,
        notification: { title: payload.title, body: payload.body },
        data: payload.data ?? {},
        android: { priority: 'high' },
      });

      this.logger.log(
        `[FCM] Multicast: ${response.successCount}/${tokens.length} delivered`,
      );

      // Auto-clean stale tokens from DB
      response.responses.forEach((resp, idx) => {
        const code = resp.error?.code ?? '';
        if (
          !resp.success &&
          (code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token')
        ) {
          this.clearStaleToken(tokens[idx]).catch(() => {});
        }
      });
    } catch (error) {
      this.logger.error('[FCM] Multicast failed', error);
    }
  }

  // ── Stale token cleanup ───────────────────────────────────────────────────

  private async clearStaleToken(fcmToken: string): Promise<void> {
    try {
      await this.usersRepository
        .createQueryBuilder()
        .update(User)
        .set({ fcmToken: null as any })
        .where('fcmToken = :fcmToken', { fcmToken })
        .execute();
      this.logger.log('[FCM] Stale token cleared from DB');
    } catch (e) {
      this.logger.error('[FCM] Failed to clear stale token', e);
    }
  }

  // ── Booking notification helpers ──────────────────────────────────────────

  async notifyWorkerNewBooking(workerId: string, bookingId: string, skill: string) {
    return this.sendToUser(workerId, {
      title: 'New Job Request',
      body: `A customer needs ${skill} help nearby.`,
      data: { type: 'new_booking', bookingId },
    });
  }

  async notifyCustomerBookingAccepted(customerId: string, workerName: string) {
    return this.sendToUser(customerId, {
      title: 'Request Accepted!',
      body: `${workerName} is on the way to your location.`,
      data: { type: 'booking_accepted' },
    });
  }

  async notifyCustomerWorkerArrived(customerId: string, arrivalOtp: string) {
    return this.sendToUser(customerId, {
      title: 'Worker has arrived!',
      body: `Arrival OTP: ${arrivalOtp}. Share this with the worker to start the job.`,
      data: { type: 'worker_arrived', otp: arrivalOtp },
    });
  }

  async notifyCustomerJobComplete(customerId: string, completionOtp: string) {
    return this.sendToUser(customerId, {
      title: 'Job marked complete',
      body: `Completion OTP: ${completionOtp}. Enter this to confirm and close the job.`,
      data: { type: 'job_complete', otp: completionOtp },
    });
  }

  async notifyBookingCancelled(userId: string, reason?: string) {
    return this.sendToUser(userId, {
      title: 'Booking Cancelled',
      body: reason ?? 'Your booking has been cancelled.',
      data: { type: 'booking_cancelled' },
    });
  }

  async notifyGpsStrike(workerId: string, strikeCount: number) {
    return this.sendToUser(workerId, {
      title: 'GPS Warning',
      body: `Strike ${strikeCount}/3: Please head to the service location or the job will be forfeited.`,
      data: { type: 'gps_strike', strike: strikeCount.toString() },
    });
  }
}
