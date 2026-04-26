import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EntityManager } from 'typeorm';
import * as admin from 'firebase-admin';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class NotificationsService implements OnModuleInit {
  private readonly logger = new Logger(NotificationsService.name);
  private messaging: admin.messaging.Messaging | null = null;

  constructor(
    private readonly configService: ConfigService,
    private readonly entityManager: EntityManager,
    private readonly redisService: RedisService,
  ) {}

  // ── Init ──────────────────────────────────────────────────

  onModuleInit() {
    const projectId = this.configService.get<string>('FIREBASE_PROJECT_ID');
    const clientEmail = this.configService.get<string>('FIREBASE_CLIENT_EMAIL');
    const privateKey = this.configService
      .get<string>('FIREBASE_PRIVATE_KEY')
      ?.replace(/\\n/g, '\n'); // env vars flatten newlines

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'Firebase credentials not set — push notifications disabled. ' +
          'Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY in .env',
      );
      return;
    }

    // Avoid re-initialising if another module already did so
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId,
          clientEmail,
          privateKey,
        }),
      });
    }

    this.messaging = admin.messaging();
    this.logger.log('Firebase Admin SDK initialised');
  }

  // ── Core send ─────────────────────────────────────────────

  /**
   * Send a push notification to a single device by FCM token.
   *
   * NestJS stores the user's FCM token (sent by Flutter after login via
   * PATCH /auth/fcm-token). Call this method with that stored token.
   */
  async sendToDevice(payload: {
    fcmToken: string;
    title: string;
    body: string;
    data?: Record<string, string>; // FCM data payload — values must be strings
  }): Promise<boolean> {
    if (!this.messaging) {
      this.logger.warn('Firebase not initialised — skipping push');
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
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
      });

      this.logger.log(`Push sent — messageId: ${messageId}`);
      return true;
    } catch (error) {
      this.logger.error('Failed to send push notification', error);
      return false;
    }
  }

  /**
   * Send to multiple devices at once (up to 500 tokens per batch).
   */
  async sendToDevices(payload: {
    fcmTokens: string[];
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<void> {
    if (!this.messaging || payload.fcmTokens.length === 0) return;

    try {
      const response = await this.messaging.sendEachForMulticast({
        tokens: payload.fcmTokens,
        notification: { title: payload.title, body: payload.body },
        data: payload.data ?? {},
        android: { priority: 'high' },
      });

      this.logger.log(
        `Multicast: ${response.successCount} sent, ${response.failureCount} failed`,
      );
    } catch (error) {
      this.logger.error('Failed to send multicast push', error);
    }
  }

  // ── Core send to User ──────────────────────────────────────

  /**
   * Send a push notification to a user by their user ID.
   * This fetches the user's FCM token from the database.
   */
  async sendToUser(userId: string, payload: {
    title: string;
    body: string;
    data?: Record<string, string>;
  }): Promise<boolean> {
    try {
      // 1. Try Redis cache first
      let fcmToken = await this.redisService.getCachedFcmToken(userId);

      if (!fcmToken) {
        // 2. Fallback to DB query
        const user = await this.entityManager.query(
          `SELECT "fcmToken" FROM "users" WHERE "id" = $1 LIMIT 1`,
          [userId],
        );
        
        if (user && user.length > 0 && user[0].fcmToken) {
          fcmToken = user[0].fcmToken;
          // 3. Update cache for next time
          await this.redisService.cacheFcmToken(userId, fcmToken!);
        }
      }
      
      if (fcmToken) {
        return this.sendToDevice({
          fcmToken,
          ...payload,
        });
      } else {
        this.logger.warn(`No FCM token found for user ${userId}`);
        return false;
      }
    } catch (e) {
      this.logger.error(`Error fetching FCM token for user ${userId}`, e);
      return false;
    }
  }
}
