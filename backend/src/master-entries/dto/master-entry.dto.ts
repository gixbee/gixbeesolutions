import { IsString, IsNotEmpty, IsOptional, IsEnum, IsBoolean, IsUUID, ValidateIf } from 'class-validator';
import { MasterEntryType } from '../master-entry.entity';

// DTOs for the admin-only master-entries write endpoints (POST / PATCH), both
// guarded by JwtAuthGuard + AdminGuard. The global ValidationPipe (whitelist +
// transform, main.ts) only enforces when @Body() is typed with a class carrying
// class-validator metadata; until now both routes used `@Body() any`, so the
// pipe was a no-op here. Field names mirror EXACTLY the super-admin Angular
// client (super-admin-web/.../core/services/master-entries.service.ts →
// MasterEntry / Partial<MasterEntry> payloads built in
// features/master-entries/master-entries.component.ts) so `whitelist:true`
// strips nothing the client legitimately sends.

// CREATE (POST /master-entries) — the Angular form always sends `type` + `label`,
// and `value` (a text key for CATEGORY/SERVICE/ROLE/CONFIGURATION/DEAL, or the
// uploaded image URL for BANNER). All three map to NON-nullable columns, so they
// are required here — previously a missing one reached Postgres and 500'd on the
// NOT NULL constraint, so requiring them only upgrades that to a clean 400.
// icon/category are nullable columns (optional in the form); isActive defaults to
// true on the entity but the form always sends it.
export class CreateMasterEntryDto {
  @IsEnum(MasterEntryType)
  type: MasterEntryType;

  @IsString()
  @IsNotEmpty()
  label: string;

  @IsString()
  @IsNotEmpty()
  value: string;

  @IsOptional()
  @IsString()
  icon?: string;

  @IsOptional()
  @IsString()
  category?: string;

  // Location scope — a City.id from the cities master, or null/absent for
  // GLOBAL (shown in every city). ValidateIf skips the UUID check for an
  // explicit null, which the form sends when "All cities" is selected.
  @IsOptional()
  @ValidateIf((_, v) => v !== null)
  @IsUUID()
  cityId?: string | null;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}

// UPDATE (PATCH /master-entries/:id) — a partial: the quick Enable/Disable toggle
// PATCHes a body of ONLY { isActive }, and the edit modal sends an arbitrary
// subset, so every field is optional. The edit modal echoes back id/createdAt/
// updatedAt from the fetched row; those are intentionally NOT declared, so
// whitelist strips them (the service Object.assigns the body onto the loaded
// entity — dropping the PK + timestamps is the safe, correct outcome). When
// label/value ARE present they must still be non-empty (mirrors the form's
// `required`).
export class UpdateMasterEntryDto {
  @IsOptional()
  @IsEnum(MasterEntryType)
  type?: MasterEntryType;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  label?: string;

  @IsOptional()
  @IsString()
  @IsNotEmpty()
  value?: string;

  @IsOptional()
  @IsString()
  icon?: string;

  @IsOptional()
  @IsString()
  category?: string;

  // null is a legitimate PATCH value — clears a scoped entry back to global.
  @IsOptional()
  @ValidateIf((_, v) => v !== null)
  @IsUUID()
  cityId?: string | null;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
