import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  SetActiveSkillsDto,
  RegisterWorkerDto,
  UpdateRateDto,
} from './workers.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// workers write DTOs. Optionality mirrors the controller's prior tolerance:
// active-skills stays optional (empty == "all services active"), register +
// rate require their structural fields.
describe('SetActiveSkillsDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: SetActiveSkillsDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts a skills array', async () => {
    const out = await transform({ skills: ['CLEANING', 'PLUMBING'] });
    expect(out).toBeInstanceOf(SetActiveSkillsDto);
    expect(out.skills).toEqual(['CLEANING', 'PLUMBING']);
  });

  it('accepts an empty body (skills omitted → controller defaults to [])', async () => {
    const out = await transform({});
    expect(out.skills).toBeUndefined();
  });

  it('rejects a non-array skills value', async () => {
    await expect(
      transform({ skills: 'CLEANING' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a skills array with non-string members', async () => {
    await expect(
      transform({ skills: ['CLEANING', 5] }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('RegisterWorkerDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: RegisterWorkerDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full payload', async () => {
    const out = await transform({
      skills: ['CLEANING'],
      hourlyRate: 200,
      bio: 'Experienced cleaner',
      title: 'Pro Cleaner',
    });
    expect(out).toBeInstanceOf(RegisterWorkerDto);
    expect(out.skills).toEqual(['CLEANING']);
    expect(out.hourlyRate).toBe(200);
  });

  it('accepts the minimal payload (no bio/title)', async () => {
    const out = await transform({ skills: ['PLUMBING'], hourlyRate: 150 });
    expect(out.bio).toBeUndefined();
    expect(out.title).toBeUndefined();
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      skills: ['CLEANING'],
      hourlyRate: 200,
      searchRank: 9999,
    });
    expect((out as any).searchRank).toBeUndefined();
  });

  it('rejects a missing skills array', async () => {
    await expect(
      transform({ hourlyRate: 200 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-numeric hourlyRate', async () => {
    await expect(
      transform({ skills: ['CLEANING'], hourlyRate: 'lots' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('UpdateRateDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: UpdateRateDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts a numeric hourlyRate', async () => {
    const out = await transform({ hourlyRate: 250 });
    expect(out).toBeInstanceOf(UpdateRateDto);
    expect(out.hourlyRate).toBe(250);
  });

  it('rejects a missing hourlyRate', async () => {
    await expect(transform({})).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-numeric hourlyRate', async () => {
    await expect(
      transform({ hourlyRate: 'free' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
