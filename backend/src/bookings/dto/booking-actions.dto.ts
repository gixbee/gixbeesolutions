import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsEnum,
  IsInt,
  Min,
  Max,
} from 'class-validator';
import { BookingStatus } from '../booking.entity';

// Single-prop write bodies on BookingsController that were previously typed as
// inline `@Body() body: { ... }` literals (so the global ValidationPipe was a
// no-op on them). Each optionality below is traced against the ONLY real client
// caller in lib/repositories/booking_repository.dart.

// PATCH /bookings/:id/status — updateBookingStatus() posts `{ status }`.
// The admin/override generic status update; enum-validate so a bogus status
// string can't reach the service / DB.
export class UpdateBookingStatusDto {
  @IsEnum(BookingStatus)
  status: BookingStatus;
}

// PATCH /bookings/:id/cancel — cancelBooking() posts `{ reason }` (the client
// defaults it to 'Not specified', so it is always present). The controller
// already falls back via `body?.reason ?? 'Not specified'`, so reason stays
// OPTIONAL here to preserve that behaviour and never 400 a valid cancel.
export class CancelBookingDto {
  @IsOptional()
  @IsString()
  reason?: string;
}

// POST /bookings/:id/arrival and POST /bookings/:id/completion — both post
// `{ otp }` (confirmArrival / confirmCompletion). OTP is a server-generated
// 4-digit numeric string; kept as a non-empty string (not a fixed-length regex)
// to stay permissive if the OTP format ever changes.
export class ConfirmOtpDto {
  @IsString()
  @IsNotEmpty()
  otp: string;
}

// POST /bookings/:id/rating — submitRating() posts `{ rating }` as an int from
// the 5-star widget. The service has no bounds check and folds rating into the
// worker's running average, so clamp to 1..5 here to stop a tampered request
// (e.g. rating: 1000) from skewing every worker score.
export class SubmitRatingDto {
  @IsInt()
  @Min(1)
  @Max(5)
  rating: number;
}

// POST /bookings/:id/dispute — reportDispute() posts `{ reason }` (required;
// the controller interpolates it into the response message).
export class ReportDisputeDto {
  @IsString()
  @IsNotEmpty()
  reason: string;
}

// PATCH /bookings/admin/disputes/:id/resolve — admin closes a report with a
// resolution note (portal Disputes page).
export class ResolveDisputeDto {
  @IsString()
  @IsNotEmpty()
  resolution: string;
}

// PATCH /bookings/:id/mark-paid — worker and/or customer confirm offline
// collection (cash / UPI / other). Body fields are role-specific and optional
// so a bare confirm still works for older clients.
export class MarkPaidDto {
  /** Customer's off-app method: CASH | UPI | OTHER */
  @IsOptional()
  @IsString()
  collectionMethod?: string;

  /** Worker honesty: EXACT | TIP | UNDERPAID */
  @IsOptional()
  @IsString()
  honestyCheck?: string;

  /** Customer safety: OK | ASKED_MORE | TIP */
  @IsOptional()
  @IsString()
  safetyCheck?: string;
}
