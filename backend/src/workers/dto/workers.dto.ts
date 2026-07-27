import { IsString, IsNotEmpty, IsOptional, IsNumber, IsArray, IsIn, IsInt, IsBoolean, MaxLength, Min, Max } from 'class-validator';

// DTOs for the workers write endpoints.

// PATCH /workers/me/active-skills — worker_repository.setActiveSkills always
// sends { skills: [...] }, but the controller tolerates a missing/empty body
// (`body?.skills ?? []`, empty == "all services active"). Keep skills OPTIONAL
// so an empty payload still resolves to [] instead of 400-ing.
export class SetActiveSkillsDto {
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  skills?: string[];
}

// POST /workers/register (DEFECT-006) — body forwarded wholesale to
// WorkersService.createProfile({ skills, hourlyRate, bio?, title? }).
export class RegisterWorkerDto {
  @IsArray()
  @IsString({ each: true })
  skills: string[];

  @IsNumber()
  hourlyRate: number;

  @IsOptional()
  @IsString()
  bio?: string;

  @IsOptional()
  @IsString()
  title?: string;
}

// PATCH /workers/rate (DEFECT-007) — single hourlyRate field.
export class UpdateRateDto {
  @IsNumber()
  hourlyRate: number;
}

// PATCH /workers/me/languages — languages the pro speaks (v126 language
// matching). Empty array is allowed (= clear back to "unknown").
export class UpdateLanguagesDto {
  @IsArray()
  @IsString({ each: true })
  languages: string[];
}

// PATCH /workers/me/service-radius — how far the pro will travel for instant
// jobs. Validated here AND clamped in the service (defence in depth): 50 km is
// the hard dispatch ceiling, so nobody can opt into the whole state.
export class UpdateServiceRadiusDto {
  @IsInt()
  @Min(1)
  @Max(50)
  serviceRadiusKm: number;
}

// POST /workers/live-toggle — optional GPS so Instant Help can match this
// worker immediately (without waiting for a post-accept location stream).
export class LiveToggleDto {
  @IsOptional()
  @IsNumber()
  lat?: number;

  @IsOptional()
  @IsNumber()
  lng?: number;
}

// PATCH /workers/me/location — refresh Redis + last known DB coords while live.
export class UpdateLocationDto {
  @IsNumber()
  lat: number;

  @IsNumber()
  lng: number;
}

// PATCH /workers/admin/:userId/verification — admin approves/rejects a
// worker's verification from the portal queue.
export class SetWorkerVerificationDto {
  @IsIn(['VERIFIED', 'REJECTED'])
  status: 'VERIFIED' | 'REJECTED';
}

// POST /workers/me/strikes/:id/appeal — the worker's side of the story.
// One appeal per strike; admin resolves via ResolveStrikeDto below.
export class AppealStrikeDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(1000)
  message: string;
}

// PATCH /workers/admin/strikes/:id/resolve — admin overturns or upholds an
// appealed strike. `note` is shown to the worker, so write it for them.
export class ResolveStrikeDto {
  @IsBoolean()
  overturn: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string;
}
