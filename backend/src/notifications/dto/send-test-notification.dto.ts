import { IsString, IsNotEmpty, IsOptional } from 'class-validator';

// POST /notifications/test — this is a PUBLIC diagnostic route (no JwtAuthGuard),
// so hardening its input is worthwhile in its own right. No production client
// calls it (the Flutter app uses the authed /notifications/test-self; the
// super-admin portal does not call it at all), so requiring fcmToken cannot break
// a live caller. The controller already coalesces title/message to defaults
// (`body.title || '...'`), so those stay optional; `data` is free-form push
// payload. Mirrors the previous inline literal
// ({ fcmToken: string; title: string; message: string; data?: any }) with
// fcmToken now genuinely required.
export class SendTestNotificationDto {
  @IsString()
  @IsNotEmpty()
  fcmToken: string;

  @IsOptional()
  @IsString()
  title?: string;

  @IsOptional()
  @IsString()
  message?: string;

  @IsOptional()
  data?: any;
}
