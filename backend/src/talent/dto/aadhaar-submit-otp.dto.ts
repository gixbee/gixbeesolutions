import { IsString, Matches } from 'class-validator';

export class AadhaarSubmitOtpDto {
  @IsString()
  clientId: string;

  @IsString()
  @Matches(/^\d{6}$/, { message: 'otp must be 6 digits' })
  otp: string;
}
