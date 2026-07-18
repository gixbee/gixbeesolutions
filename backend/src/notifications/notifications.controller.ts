import { Controller, Post, Get, HttpCode, HttpStatus, UseGuards, Req } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

// SECURITY FIX: the whole controller is now JWT-guarded, and the old
// unauthenticated `POST /notifications/test` (which pushed an
// attacker-supplied title/body to any fcmToken — a targeted phishing vector)
// is removed. Legitimate testing uses `test-self`, which only pushes to the
// caller's own device.
@UseGuards(JwtAuthGuard)
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  /** Check if Firebase Admin SDK is initialized and ready */
  @Get('health')
  async getHealth() {
    return this.notificationsService.getDiagnostics();
  }

  /** Send a test push to the currently authenticated user's device */
  @Post('test-self')
  @HttpCode(HttpStatus.OK)
  async testSelfPush(@Req() req) {
    const userId = req.user.userId;
    return this.notificationsService.testPushToUser(userId);
  }
}
