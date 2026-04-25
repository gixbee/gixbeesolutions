import { Controller, Post, Body, HttpCode, HttpStatus } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

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
        ? 'Notification sent successfully via OneSignal'
        : 'Failed to send notification. Check backend logs.',
    };
  }
}
