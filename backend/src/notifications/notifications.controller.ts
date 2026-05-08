import { Controller, Post, Get, Body, HttpCode, HttpStatus, UseGuards, Req } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  /** Check if Firebase Admin SDK is initialized and ready */
  @Get('health')
  @UseGuards(JwtAuthGuard)
  async getHealth() {
    return this.notificationsService.getDiagnostics();
  }

  /** Send a test push to the currently authenticated user's device */
  @Post('test-self')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.OK)
  async testSelfPush(@Req() req) {
    const userId = req.user.userId;
    return this.notificationsService.testPushToUser(userId);
  }

  @Post('test')
  @HttpCode(HttpStatus.OK)
  async sendTestNotification(
    @Body() body: { fcmToken: string; title: string; message: string; data?: any },
  ) {
    const success = await this.notificationsService.sendToDevice({
      fcmToken: body.fcmToken,
      title: body.title || 'Test Notification',
      body: body.message || 'This is a test push notification from Gixbee Backend.',
      data: body.data,
    });

    return {
      success,
      message: success
        ? 'Notification sent successfully'
        : 'Failed to send notification. Check backend logs.',
    };
  }
}
