import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsNumber,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

// POST /addresses — addresses_repository.add sends { line, label?, lat?, lng? }.
// Field names mirror EXACTLY what the Flutter client sends so the global
// ValidationPipe (whitelist + transform, main.ts) strips nothing legitimate.
// lat/lng arrive from a CONFIRMED LocationPinScreen pin — never from
// forward-geocoding — and are optional so plain text-only saves still work.
export class CreateAddressDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  line: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  label?: string;

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
}

// PATCH /addresses/:id/coords — backfill the confirmed pin onto a saved
// address that predates coordinate storage (one-time per address; afterwards
// the app reuses the pin without opening the map).
export class UpdateAddressCoordsDto {
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat: number;

  @IsNumber()
  @Min(-180)
  @Max(180)
  lng: number;
}
