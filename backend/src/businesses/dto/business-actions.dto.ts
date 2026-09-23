import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsDateString,
  IsIn,
} from 'class-validator';

// DTOs for the two single-field business write endpoints. Previously these used
// `@Body('userId')` / `@Body('date')` primitive extraction, which the global
// ValidationPipe (whitelist + transform, main.ts) cannot validate — a typed
// `@Body()` class is required for class-validator metadata to run. Field names
// mirror EXACTLY what the Flutter client sends (business_repository.dart) so
// `whitelist:true` strips nothing legitimate.

// POST /businesses/:id/operators — business_repository.addOperator sends
// { userId, role }. The controller only consumes userId; `role` is declared
// @IsOptional so whitelist keeps it on the payload rather than silently dropping
// it (it stays unused, matching current behaviour).
export class AddOperatorDto {
  @IsString()
  @IsNotEmpty()
  userId: string;

  @IsOptional()
  @IsString()
  role?: string;
}

// POST /businesses/:id/calendar/offline — business_repository.addOfflineDay sends
// { date: <ISO-8601 string> } (DateTime.toIso8601String()).
export class AddOfflineDayDto {
  @IsDateString()
  date: string;
}

// PATCH /businesses/admin/:id/status — portal moderation verdict.
export class SetBusinessStatusDto {
  @IsIn(['VERIFIED', 'REJECTED', 'PENDING', 'NEEDS_CHANGES'])
  status: 'VERIFIED' | 'REJECTED' | 'PENDING' | 'NEEDS_CHANGES';

  @IsOptional()
  @IsString()
  reviewNote?: string;
}
