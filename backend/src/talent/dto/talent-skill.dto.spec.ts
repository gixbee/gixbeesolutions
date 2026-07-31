import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  AddSkillDto,
  RemoveSkillDto,
  ToggleAlertsDto,
} from './talent-skill.dto';

// Drives the REAL global ValidationPipe (same options as main.ts) against the
// three talent skill/alert DTOs — proving the pipe now enforces input shape AND
// that it does NOT reject the legitimate Flutter client payloads.
describe('talent skill/alert DTO validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const run = (metatype: any) => (body: any) =>
    pipe.transform(body, { type: 'body', metatype, data: '' } as any);

  describe('AddSkillDto', () => {
    const transform = run(AddSkillDto);

    it('accepts the real client payload (skillName/rate/bio/rateChart)', async () => {
      const out = await transform({
        skillName: 'PLUMBING',
        rate: 250,
        bio: 'Licensed plumber',
        rateChart: { basic: 250, premium: 400 },
      });
      expect(out).toBeInstanceOf(AddSkillDto);
      expect(out.skillName).toBe('PLUMBING');
      expect(out.rate).toBe(250);
      expect(out.rateChart?.premium).toBe(400);
    });

    it('accepts an empty bio and empty rateChart (register_pro_screen path)', async () => {
      const out = await transform({
        skillName: 'CLEANING',
        rate: 150,
        bio: '',
        rateChart: {},
      });
      expect(out.bio).toBe('');
      expect(out.rateChart).toEqual({});
    });

    it('strips unknown fields (whitelist) but keeps declared ones', async () => {
      const out = await transform({
        skillName: 'CARPENTRY',
        rate: 300,
        bio: 'x',
        searchRank: 9999, // server-managed, must not be settable
      });
      expect(out.searchRank).toBeUndefined();
      expect(out.skillName).toBe('CARPENTRY');
    });

    it('rejects a missing skillName', async () => {
      await expect(transform({ rate: 100, bio: '' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('rejects an empty skillName', async () => {
      await expect(
        transform({ skillName: '', rate: 100, bio: '' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a non-numeric rate', async () => {
      await expect(
        transform({ skillName: 'X', rate: 'free', bio: '' }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('RemoveSkillDto', () => {
    const transform = run(RemoveSkillDto);

    it('accepts { skillId }', async () => {
      const out = await transform({ skillId: 'skill-1' });
      expect(out.skillId).toBe('skill-1');
    });

    it('rejects a missing skillId', async () => {
      await expect(transform({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('ToggleAlertsDto', () => {
    const transform = run(ToggleAlertsDto);

    it('accepts { enabled: true }', async () => {
      const out = await transform({ enabled: true });
      expect(out.enabled).toBe(true);
    });

    it('accepts { enabled: false }', async () => {
      const out = await transform({ enabled: false });
      expect(out.enabled).toBe(false);
    });

    it('rejects a non-boolean enabled', async () => {
      await expect(transform({ enabled: 'yes' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
  });
});
