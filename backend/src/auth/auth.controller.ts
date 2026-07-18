import { Controller, Post, Get, Patch, Body, UseGuards, Req } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import {
  RequestOtpDto,
  VerifyOtpDto,
  RefreshTokenDto,
  UpdatePushTokenDto,
  UpdateFcmTokenDto,
  AdminLoginDto,
} from './dto/auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private authService: AuthService) {}

  // Tight per-route limit so the global 100/min default can't be used to bomb
  // OTP SMS / brute-force codes (PENDING_WORK 6.5). 5 OTP requests / minute.
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @Post('request-otp')
  async requestOtp(@Body() body: RequestOtpDto) {
    return this.authService.requestOtp(body.phone);
  }

  // Allow a few verification retries but stop brute-force guessing: 10/min.
  @Throttle({ default: { ttl: 60000, limit: 10 } })
  @Post('verify-otp')
  async verifyOtp(@Body() body: VerifyOtpDto) {
    return this.authService.verifyOtp(body.phone, body.otp);
  }

  @Post('refresh')
  async refreshToken(@Body() body: RefreshTokenDto) {
    return this.authService.refreshAccessToken(body.refreshToken);
  }


  @UseGuards(AuthGuard('jwt'))
  @Get('profile')
  async getProfile(@Req() req: any) {
    return this.authService.getProfile(req.user.userId);
  }

  @UseGuards(AuthGuard('jwt'))
  @Patch('push-token')
  async updatePushToken(@Req() req: any, @Body() body: UpdatePushTokenDto) {
    return this.authService.updatePushToken(req.user.userId, body.pushToken);
  }

  // Legacy endpoint — backward compatible alias
  @UseGuards(AuthGuard('jwt'))
  @Patch('fcm-token')
  async updateFcmToken(@Req() req: any, @Body() body: UpdateFcmTokenDto) {
    return this.authService.updatePushToken(req.user.userId, body.fcmToken);
  }

  // Brute-force guard on the admin credential check: 5 attempts / minute.
  @Throttle({ default: { ttl: 60000, limit: 5 } })
  @Post('admin-login')
  async adminLogin(@Body() body: AdminLoginDto) {
    return this.authService.adminLogin(body.username || '', body.password || '');
  }
}
