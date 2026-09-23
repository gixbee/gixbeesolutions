import { IsString, IsNotEmpty, IsOptional, IsUUID, IsArray, IsIn, ArrayUnique, MaxLength, IsObject } from 'class-validator';

// POST /businesses — mirrors Flutter Business.toJson()
// (lib/shared/models/business.dart). Persisted columns: name, type,
// description, documentUrl, cityId, location (from `address`), and optional
// serviceType (SERVICE only). specialty/phone are client-only (whitelisted so
// they are not stripped; BusinessesService.create drops them).
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
  @MaxLength(30)
  phone?: string;

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsIn(['HALL', 'CATERING', 'DECORATION', 'PHOTOGRAPHY', 'DJ', 'MAKEUP', 'MEHENDI', 'INVITATIONS'], { each: true })
  eventServices?: string[];

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

  /** SERVICE only — HALL | CATERING | DECORATION | PHOTOGRAPHY. */
  @IsOptional()
  @IsString()
  serviceType?: string;

  @IsOptional()
  @IsObject()
  hiringProfile?: Record<string, unknown>;
}
