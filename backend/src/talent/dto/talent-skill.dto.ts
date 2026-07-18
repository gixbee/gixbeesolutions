import { IsString, IsNotEmpty, IsOptional, IsNumber, IsBoolean, IsObject } from 'class-validator';

// DTOs for the remaining talent write endpoints that previously used
// single-property @Body('x') extraction (primitives bypass class-validator, so
// they were unvalidated). Switching each to a whole-body DTO brings them under
// the global ValidationPipe (whitelist:true, transform:true) — same pattern as
// the auth/bookings/workers DTOs. Every field was traced against the real
// Flutter client call site so no legitimate request is rejected or stripped.

// POST /talent/skills — talent_repository.addOrUpdateSkill() always sends
// { skillName, rate, bio, rateChart }. Only caller is register_pro_screen:
//   repo.addOrUpdateSkill(entry.key, _rate, skillBio, {})
// so skillName/rate/bio are always present (bio may be an empty string) and
// rateChart is an object (commonly {}). The service signature is
// addOrUpdateSkill(userId, skillName: string, rate: number, bio: string,
// rateChart?: Record<string, number>) — DTO matches that exactly: skillName
// non-empty, rate numeric, bio a (possibly empty) string, rateChart optional.
export class AddSkillDto {
  @IsString()
  @IsNotEmpty()
  skillName: string;

  @IsNumber()
  rate: number;

  // Client always sends a string (often ''), and the service param is required
  // `bio: string`, so this is required-but-allows-empty rather than @IsOptional.
  @IsString()
  bio: string;

  // Freeform price map (skill tier -> rate). @IsObject keeps it a top-level
  // object; whitelist only strips unknown DTO props, not this object's inner
  // keys, so the rate chart passes through intact.
  @IsOptional()
  @IsObject()
  rateChart?: Record<string, number>;
}

// POST /talent/skills/remove — talent_repository.removeSkill() sends { skillId }.
export class RemoveSkillDto {
  @IsString()
  @IsNotEmpty()
  skillId: string;
}

// PATCH /talent/alerts — talent_repository.toggleAlerts() and
// hiring_repository.toggleJobAlerts() both send { enabled: bool }.
export class ToggleAlertsDto {
  @IsBoolean()
  enabled: boolean;
}

// POST /talent/saved-jobs/toggle — "Later" bookmark in the job-alerts feed
// (v126 Find a Job). Client sends { jobId } (a JobPost uuid).
export class ToggleSavedJobDto {
  @IsString()
  @IsNotEmpty()
  jobId: string;
}
