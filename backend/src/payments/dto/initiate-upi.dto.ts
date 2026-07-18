import { IsString, IsOptional, IsNumber } from 'class-validator';

// POST /payments/upi/initiate — 1:1 typed replacement of the inline @Body()
// literal ({ amount?: number; bookingId?: string }). The only caller,
// payment_repository.dart initiateUpiPayment(), always sends `amount` (double)
// and conditionally `bookingId`; the inline contract marked amount optional, so
// it is kept @IsOptional here to guarantee no well-formed request is rejected.
// (This flow is credential-blocked — the backend returns needsApiKey:true until
// the PhonePe merchant key is configured — so the DTO only hardens input shape,
// it does not move money.)
export class InitiateUpiDto {
  @IsOptional()
  @IsNumber()
  amount?: number;

  @IsOptional()
  @IsString()
  bookingId?: string;
}
