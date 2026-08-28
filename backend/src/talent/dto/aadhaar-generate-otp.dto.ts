import { IsString, Matches } from 'class-validator';

export class AadhaarGenerateOtpDto {
  @IsString()
  @Matches(/^\d{12}$/, { message: 'aadhaarNumber must be 12 digits' })
  aadhaarNumber: string;
}
