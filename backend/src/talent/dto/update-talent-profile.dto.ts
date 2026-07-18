import {
  IsString,
  IsOptional,
  IsNumber,
  IsArray,
  IsBoolean,
  IsEnum,
} from 'class-validator';

// POST /talent/profile — partial update; the service does
// Object.assign(profile, data). Two real client call paths feed this:
//   • register_pro_screen → talent_repository.updateProfile({ photoUrl, certificates })
//   • hiring_repository.saveTalentProfile → TalentProfile.toJson()
//        { skills, experience, bio, jobAlertsEnabled, isActive }
// Every USER-SETTABLE TalentProfile column is declared (all optional, since it
// is a partial update) so `whitelist:true` keeps the legitimate fields. The
// server-managed counters — noShowCount, searchRank — are intentionally OMITTED
// so a client can no longer tamper with its own search rank (whitelist strips
// them). `bio` and `isActive` are sent by TalentProfile.toJson() but are NOT
// columns on the entity, so they were already no-ops on save; whitelist now
// drops them harmlessly.
export class UpdateTalentProfileDto {
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  education?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  skills?: string[];

  @IsOptional()
  @IsString()
  photoUrl?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  certificates?: string[];

  // Expected monthly salary in ₹ (v126 Find a Job wizard salary step).
  @IsOptional()
  @IsNumber()
  expectedSalary?: number;

  @IsOptional()
  @IsString()
  experience?: string;

  @IsOptional()
  @IsNumber()
  hourlyRate?: number;

  @IsOptional()
  @IsEnum(['FINAL_YEAR', 'GRADUATE', 'EXPERIENCED'])
  currentStatus?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredRoles?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  preferredLocations?: string[];

  @IsOptional()
  @IsBoolean()
  jobAlertsEnabled?: boolean;
}
