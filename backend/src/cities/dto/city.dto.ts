import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  IsNumber,
  Min,
  Max,
} from 'class-validator';

// DTOs for the admin-only cities write endpoints (POST / PATCH), guarded by
// JwtAuthGuard + AdminGuard — same convention as master-entries. Field names
// mirror the super-admin Angular client (core/services/cities.service.ts).
export class CreateCityDto {
  @IsString()
  @IsNotEmpty()
  name: string;

  @IsString()
  @IsNotEmpty()
  state: string;

  @IsNumber()
  @Min(-90)
  @Max(90)
  lat: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  lng: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// PATCH is a partial — the quick Enable/Disable toggle sends only
// { isActive }; the edit modal sends an arbitrary subset.
export class UpdateCityDto {
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  name?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  state?: string;

  @IsOptional()
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat?: number;

  @IsOptional()
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng?: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
