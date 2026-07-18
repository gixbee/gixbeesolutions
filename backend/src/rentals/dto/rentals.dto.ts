import { IsString, IsNotEmpty, IsOptional, IsNumber, IsBoolean } from 'class-validator';

// DTOs for the rentals endpoints. Owner/renter identity comes from the JWT
// (req.user.userId) — the old spoofable ownerId/renterId body fields are gone.

// POST /rentals — owner lists an item for rent.
export class CreateRentalItemDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsNumber()
  hourlyRate: number;

  // Optional flat per-day rate; when set and the reservation spans ≥ 24h the
  // price uses ceil(days) × dailyRate instead of hours × hourlyRate.
  @IsOptional()
  @IsNumber()
  dailyRate?: number;

  @IsOptional()
  @IsNumber()
  minHoursToRent?: number;

  @IsOptional()
  @IsString()
  description?: string;

  // Uploaded via POST /uploads/image → URL.
  @IsOptional()
  @IsString()
  imageUrl?: string;
}

// PATCH /rentals/:id — owner edits their item (partial; also used for the
// availability toggle).
export class UpdateRentalItemDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  name?: string;

  @IsOptional()
  @IsNumber()
  hourlyRate?: number;

  @IsOptional()
  @IsNumber()
  dailyRate?: number;

  @IsOptional()
  @IsNumber()
  minHoursToRent?: number;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  imageUrl?: string;

  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;
}

// POST /rentals/:id/reserve — customer requests a date/time range. ISO
// strings; the controller validates parseability.
export class RequestReservationDto {
  @IsString()
  @IsNotEmpty()
  startTime: string;

  @IsString()
  @IsNotEmpty()
  endTime: string;
}
