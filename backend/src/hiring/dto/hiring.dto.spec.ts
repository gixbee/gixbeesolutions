import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  CreateJobPostDto,
  ApplyForJobDto,
  UpdateApplicationStatusDto,
} from './hiring.dto';
import { ApplicationStatus } from '../job-application.entity';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// hiring write DTOs. The full client payload is JobPost.toJson()
// (lib/shared/models/job_post.dart): title, description, requiredSkills,
// salaryMin, salaryMax, jobType, experience, location — every field is declared
// so whitelist strips nothing. applyToJob (hiring_repository.dart) sends a body
// of { coverLetter } which may be null.
describe('CreateJobPostDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateJobPostDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full JobPost.toJson() client payload', async () => {
    const out = await transform({
      title: 'Senior Plumber',
      description: 'Lead residential plumbing jobs.',
      requiredSkills: ['PLUMBING', 'PIPEFITTING'],
      salaryMin: 25000,
      salaryMax: 45000,
      jobType: 'Full Time',
      experience: 'Senior',
      location: 'Bengaluru',
    });
    expect(out).toBeInstanceOf(CreateJobPostDto);
    expect(out.title).toBe('Senior Plumber');
    expect(out.requiredSkills).toEqual(['PLUMBING', 'PIPEFITTING']);
  });

  it('accepts a minimal payload (only title + description required)', async () => {
    const out = await transform({
      title: 'Helper',
      description: 'General help.',
    });
    expect(out.requiredSkills).toBeUndefined();
    expect(out.salaryMin).toBeUndefined();
  });

  it('accepts null salaryMin/salaryMax (client sends null when unset)', async () => {
    const out = await transform({
      title: 'Helper',
      description: 'General help.',
      salaryMin: null,
      salaryMax: null,
    });
    expect(out.title).toBe('Helper');
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      title: 'Helper',
      description: 'General help.',
      isFeatured: true,
    });
    expect(out.isFeatured).toBeUndefined();
  });

  it('rejects a missing title', async () => {
    await expect(
      transform({ description: 'No title here.' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty-string description', async () => {
    await expect(
      transform({ title: 'Helper', description: '' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-array requiredSkills', async () => {
    await expect(
      transform({ title: 'X', description: 'Y', requiredSkills: 'PLUMBING' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-numeric salaryMin', async () => {
    await expect(
      transform({ title: 'X', description: 'Y', salaryMin: 'lots' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('ApplyForJobDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: ApplyForJobDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts a cover letter', async () => {
    const out = await transform({ coverLetter: 'I am keen on this role.' });
    expect(out).toBeInstanceOf(ApplyForJobDto);
    expect(out.coverLetter).toBe('I am keen on this role.');
  });

  it('accepts an empty body (coverLetter omitted)', async () => {
    const out = await transform({});
    expect(out.coverLetter).toBeUndefined();
  });

  it('accepts a null coverLetter (client may send null)', async () => {
    const out = await transform({ coverLetter: null });
    expect(out.coverLetter).toBeNull();
  });

  it('rejects a non-string coverLetter', async () => {
    await expect(transform({ coverLetter: 42 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});

describe('UpdateApplicationStatusDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = {
    type: 'body',
    metatype: UpdateApplicationStatusDto,
    data: '',
  } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the uppercase status the client sends', async () => {
    const out = await transform({ status: ApplicationStatus.SELECTED });
    expect(out).toBeInstanceOf(UpdateApplicationStatusDto);
    expect(out.status).toBe(ApplicationStatus.SELECTED);
  });

  it('rejects a value outside the enum', async () => {
    await expect(transform({ status: 'NOPE' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects a missing status', async () => {
    await expect(transform({})).rejects.toBeInstanceOf(BadRequestException);
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      status: ApplicationStatus.SELECTED,
      hacker: 1,
    });
    expect(out.hacker).toBeUndefined();
  });
});
