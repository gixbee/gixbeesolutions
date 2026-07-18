import { IsString, IsNotEmpty, IsOptional, MaxLength } from 'class-validator';

// POST /addresses — addresses_repository.add sends { line, label? }. Field names
// mirror EXACTLY what the Flutter client sends so the global ValidationPipe
// (whitelist + transform, main.ts) strips nothing legitimate.
export class CreateAddressDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(500)
  line: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  label?: string;
}
