import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { UpdateTalentProfileDto } from './update-talent-profile.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against
// UpdateTalentProfileDto. POST /talent/profile is a partial update, so every
// field is optional — the pipe must accept BOTH real client call paths and
// must STRIP server-managed counters (noShowCount, searchRank) so a client can
// no longer tamper with its own search rank.
describe('UpdateTalentProfileDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = {
    type: 'body',
    metatype: UpdateTalentProfileDto,
    data: '',
  } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the register_pro path ({ photoUrl, certificates })', async () => {
    const out = await transform({
      photoUrl: 'https://cdn/x.png',
      certificates: ['cert1', 'cert2'],
    });
    expect(out).toBeInstanceOf(UpdateTalentProfileDto);
    expect(out.photoUrl).toBe('https://cdn/x.png');
    expect(out.certificates).toEqual(['cert1', 'cert2']);
  });

  it('accepts the TalentProfile.toJson path ({ skills, experience, jobAlertsEnabled })', async () => {
    const out = await transform({
      skills: ['DESIGN'],
      experience: '3 years',
      jobAlertsEnabled: true,
    });
    expect(out.skills).toEqual(['DESIGN']);
    expect(out.jobAlertsEnabled).toBe(true);
  });

  it('accepts an empty partial body', async () => {
    const out = await transform({});
    expect(out).toBeInstanceOf(UpdateTalentProfileDto);
  });

  it('strips server-managed counters (searchRank, noShowCount)', async () => {
    const out = await transform({
      skills: ['DESIGN'],
      searchRank: 99999,
      noShowCount: -50,
    });
    expect(out.searchRank).toBeUndefined();
    expect(out.noShowCount).toBeUndefined();
    expect(out.skills).toEqual(['DESIGN']);
  });

  it('strips non-column fields sent by toJson (bio, isActive)', async () => {
    const out = await transform({
      skills: ['DESIGN'],
      bio: 'x',
      isActive: true,
    });
    expect(out.bio).toBeUndefined();
    expect(out.isActive).toBeUndefined();
  });

  it('accepts a valid currentStatus enum value', async () => {
    const out = await transform({ currentStatus: 'GRADUATE' });
    expect(out.currentStatus).toBe('GRADUATE');
  });

  it('rejects an invalid currentStatus enum value', async () => {
    await expect(transform({ currentStatus: 'ALIEN' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects a non-array skills value', async () => {
    await expect(transform({ skills: 'DESIGN' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects a non-boolean jobAlertsEnabled', async () => {
    await expect(transform({ jobAlertsEnabled: 'yes' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});
