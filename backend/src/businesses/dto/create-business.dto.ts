import { IsString, IsNotEmpty, IsOptional, IsUUID } from 'class-validator';

// POST /businesses — mirrors Flutter Business.toJson()
// (lib/shared/models/business.dart). Persisted columns: name, type,
// description, documentUrl, cityId, and location (mapped from `address`).
// specialty/phone are client-only (whitelisted so they are not stripped;
// BusinessesService.create drops them).
export class CreateBusinessDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsNotEmpty()
  type: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  specialty?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  /** Free-text address → persisted as Business.location for admin review. */
  @IsString()
  @IsNotEmpty()
  address: string;

  // Optional uploaded registration/tax-ID document URL (persisted column).
  @IsOptional()
  @IsString()
  documentUrl?: string;

  // Optional structured city scope — City.id from the cities master
  // (persisted column; filtering uses this, `address`/`location` stay
  // free-text display strings).
  @IsOptional()
  @IsUUID()
  cityId?: string;
}
