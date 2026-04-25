import { Controller, Post, Get, Patch, Body, UseGuards, Req } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { AuthService } from './auth.service';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  @Post('request-otp')
  async requestOtp(@Body() body: { phone: string }) {
    return this.authService.requestOtp(body.phone);
  }

  @Post('verify-otp')
  async verifyOtp(@Body() body: { phone: string, otp: string }) {
    return this.authService.verifyOtp(body.phone, body.otp);
  }



  @UseGuards(AuthGuard('jwt'))
  @Get('profile')
  async getProfile(@Req() req: any) {
    return this.authService.getProfile(req.user.userId);
  }

  @UseGuards(AuthGuard('jwt'))
  @Patch('push-token')
  async updatePushToken(@Req() req: any, @Body() body: { pushToken: string }) {
    return this.authService.updatePushToken(req.user.userId, body.pushToken);
  }

  // Legacy endpoint — backward compatible alias
  @UseGuards(AuthGuard('jwt'))
  @Patch('fcm-token')
  async updateFcmToken(@Req() req: any, @Body() body: { fcmToken: string }) {
    return this.authService.updatePushToken(req.user.userId, body.fcmToken);
  }

  @Post('admin-login')
  async adminLogin(@Body() body: { username?: string, password?: string }) {
    return this.authService.adminLogin(body.username || '', body.password || '');
  }
}
