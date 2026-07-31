import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsNumber,
  IsArray,
  IsEnum,
} from 'class-validator';
import { ApplicationStatus } from '../job-application.entity';

// DTOs for the hiring write endpoints. The global ValidationPipe
// (whitelist + transform, main.ts) only enforces when the @Body() param is
// typed with a class carrying class-validator metadata. Field names mirror
// EXACTLY what the Flutter client sends (hiring_repository.dart →
// JobPost.toJson / applyToJob) so `whitelist:true` strips nothing legitimate.

// POST /hiring/jobs — JobPost.toJson() sends title, description, requiredSkills,
// salaryMin, salaryMax, and also jobType/experience/location. The controller
// only forwards the first five to the service; the extra three are accepted
// (so whitelist doesn't strip a field the client sends) but stay unused.
// title + description are the only hard-required fields (the controller throws
// BadRequest without them), matching the manual guard already in place.
export class CreateJobPostDto {
  @IsString()
  @IsNotEmpty()
  title: string;

  @IsString()
  @IsNotEmpty()
  description: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  requiredSkills?: string[];

  @IsOptional()
  @IsNumber()
  salaryMin?: number;

  @IsOptional()
  @IsNumber()
  salaryMax?: number;

  // Sent by JobPost.toJson() — persisted since 2026-07-13 (entity columns
  // jobType/experience/location) so seeker-side filters use real data.
  @IsOptional()
  @IsString()
  jobType?: string;

  @IsOptional()
  @IsString()
  experience?: string;

  @IsOptional()
  @IsString()
  location?: string;
}

// POST /hiring/jobs/:id/apply — body carries an optional cover letter and an
// optional résumé URL (hiring_repository.applyToJob sends { coverLetter,
// resumeUrl }, either of which may be null/omitted).
export class ApplyForJobDto {
  @IsOptional()
  @IsString()
  coverLetter?: string;

  @IsOptional()
  @IsString()
  resumeUrl?: string;
}

// PATCH /hiring/applications/:id/status — hiring_repository.updateApplicationStatus
// sends { status: '<UPPERCASE ApplicationStatus>' }. @IsEnum rejects any value
// outside the enum at the pipe; the controller keeps its manual guard too (the
// pipe only runs in the HTTP layer, not on direct unit-test method calls).
export class UpdateApplicationStatusDto {
  @IsEnum(ApplicationStatus)
  status: ApplicationStatus;
}
