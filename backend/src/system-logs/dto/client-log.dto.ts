import { IsString, IsOptional, MaxLength } from 'class-validator';

/**
 * Payload sent by the Flutter app when an unhandled error or crash occurs.
 * Kept lean — the app only needs to send the error + stack trace; metadata
 * like userId and IP are extracted server-side from the JWT / request.
 */
export class ClientLogDto {
  @IsString()
  @MaxLength(500)
  error: string;

  @IsOptional()
  @IsString()
  @MaxLength(8000)
  stackTrace?: string;

  /** e.g. 'FlutterError', 'PlatformError', 'NetworkError' */
  @IsOptional()
  @IsString()
  @MaxLength(100)
  errorType?: string;

  /** App screen / route where the crash happened, if available. */
  @IsOptional()
  @IsString()
  @MaxLength(200)
  screen?: string;

  /** App version string from AppConfig.buildVersion */
  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;

  /** Device info: 'Android 14 / Pixel 7' or 'iOS 17.4 / iPhone 15' */
  @IsOptional()
  @IsString()
  @MaxLength(200)
  device?: string;
}
