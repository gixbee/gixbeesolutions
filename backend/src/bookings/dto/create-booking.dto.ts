import {
  IsString,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsEnum,
  IsArray,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { BookingType } from '../booking.entity';

// On-site contact for instant bookings. The client (presence_check_screen.dart
// `OnSiteContact.toMap()`) always sends all three as non-null strings, and the
// service contract types them required, so they are required here too. The
// whole onSiteContact object stays optional on CreateBookingDto.
export class OnSiteContactDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsNotEmpty()
  relation: string;

  @IsString()
  @IsNotEmpty()
  phone: string;
}

// CreateBookingDto — validates POST /bookings. Field set + optionality mirror
// BOTH real client call paths (booking_repository.dart):
//   • createBooking()      (scheduled/package): workerId, scheduledAt, amount,
//                          serviceLocation, [description], [skill], paymentMethod
//                          — NO serviceLat/Lng/type
//   • sendInstantRequest() (instant): workerId, skill, serviceLocation,
//                          serviceLat, serviceLng, amount, scheduledAt,
//                          type='INSTANT', [onSiteContact], paymentMethod
// So only workerId / serviceLocation / scheduledAt / amount are truly always
// present; everything else is @IsOptional to avoid 400-ing a valid request.
// (whitelist:true strips undecorated extras like `description` harmlessly.)
export class CreateBookingDto {
  @IsString()
  @IsNotEmpty()
  workerId: string;

  @IsOptional()
  @IsString()
  skill?: string;

  @IsString()
  @IsNotEmpty()
  serviceLocation: string;

  @IsOptional()
  @IsNumber()
  serviceLat?: number;

  @IsOptional()
  @IsNumber()
  serviceLng?: number;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => OnSiteContactDto)
  onSiteContact?: OnSiteContactDto;

  // ISO 8601 string; the controller wraps it in `new Date(...)`. Kept as a
  // non-empty string (not @IsDateString) to stay permissive about formats.
  @IsString()
  @IsNotEmpty()
  scheduledAt: string;

  @IsNumber()
  amount: number;

  @IsOptional()
  @IsEnum(BookingType)
  type?: BookingType;

  @IsOptional()
  @IsString()
  paymentMethod?: string;

  // Optional id of the saved Address the customer picked. The free-text
  // serviceLocation is still always sent; this just links the booking back to
  // the chosen saved entry (when the user tapped one rather than free-typing).
  @IsOptional()
  @IsString()
  addressId?: string;
}

// POST /bookings/instant — v126 broadcast dispatch. NO workerId: every nearby
// live pro with the skill is notified and the first to accept is assigned.
// lat/lng are REQUIRED (the geo fan-out needs them); amount is the customer's
// offered ₹/hr budget.
export class CreateInstantRequestDto {
  @IsString()
  @IsNotEmpty()
  skill: string;

  // Selected issue chips + optional free text — persisted and shown to the
  // notified pros before they accept.
  @IsOptional()
  @IsString()
  description?: string;

  // v126 language step — languages the pro must speak.
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredLanguages?: string[];

  @IsString()
  @IsNotEmpty()
  serviceLocation: string;

  @IsNumber()
  serviceLat: number;

  @IsNumber()
  serviceLng: number;

  @IsNumber()
  amount: number;

  @IsOptional()
  @IsString()
  addressId?: string;

  @IsOptional()
  @IsString()
  paymentMethod?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => OnSiteContactDto)
  onSiteContact?: OnSiteContactDto;
}
