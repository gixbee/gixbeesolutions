import { IsString, IsNotEmpty, IsOptional } from 'class-validator';

// DTOs for the auth write endpoints. ValidationPipe (whitelist + transform,
// wired globally in main.ts) only enforces when the @Body() is typed with a
// class that carries class-validator metadata — these classes turn the
// previously type-only (runtime no-op) bodies into real input validation.
// Field names mirror EXACTLY what the Flutter client sends (auth_repository.dart)
// so nothing legitimate is stripped by `whitelist: true`.

export class RequestOtpDto {
  @IsString()
  @IsNotEmpty()
  phone: string;
}

export class VerifyOtpDto {
  @IsString()
  @IsNotEmpty()
  phone: string;

  @IsString()
  @IsNotEmpty()
  otp: string;
}

export class RefreshTokenDto {
  @IsString()
  @IsNotEmpty()
  refreshToken: string;
}

export class UpdatePushTokenDto {
  @IsString()
  @IsNotEmpty()
  pushToken: string;
}

export class UpdateFcmTokenDto {
  @IsString()
  @IsNotEmpty()
  fcmToken: string;
}

// Username/password kept optional: the controller already coalesces missing
// values to '' (`body.username || ''`), so requiring them here would change a
// 401 (bad credentials) into a 400 (validation). Preserve existing behaviour.
export class AdminLoginDto {
  @IsOptional()
  @IsString()
  username?: string;

  @IsOptional()
  @IsString()
  password?: string;
}
