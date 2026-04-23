import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';

@Injectable()
export class NotificationsService implements OnModuleInit {
  private readonly logger = new Logger(NotificationsService.name);
  private messaging: admin.messaging.Messaging | null = null;

  constructor(private readonly configService: ConfigService) {}

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

  // ── Booking-specific helpers ──────────────────────────────
  // These are called by bookings.service.ts, workers.service.ts, etc.
  // Each method looks up the user's stored FCM token from the users table
  // and calls sendToDevice().

  async notifyWorkerNewBooking(fcmToken: string, bookingId: string) {
    await this.sendToDevice({
      fcmToken,
      title: 'New Job Request',
      body: 'A customer has requested your services.',
      data: { type: 'new_booking', bookingId },
    });
  }

  async notifyCustomerBookingAccepted(fcmToken: string, workerName: string) {
    await this.sendToDevice({
      fcmToken,
      title: 'Request Accepted!',
      body: `${workerName} is on the way.`,
      data: { type: 'booking_accepted' },
    });
  }

  async notifyWorkerArrived(fcmToken: string, otp: string) {
    await this.sendToDevice({
      fcmToken,
      title: 'Worker Has Arrived',
      body: `Your arrival OTP is ${otp}`,
      data: { type: 'worker_arrived', otp },
    });
  }

  async notifyJobCompleted(fcmToken: string) {
    await this.sendToDevice({
      fcmToken,
      title: 'Job Completed',
      body: 'Your service has been completed. Please leave a review.',
      data: { type: 'job_completed' },
    });
  }

  async notifyBookingCancelled(fcmToken: string) {
    await this.sendToDevice({
      fcmToken,
      title: 'Booking Cancelled',
      body: 'Your booking has been cancelled.',
      data: { type: 'booking_cancelled' },
    });
  }
}
