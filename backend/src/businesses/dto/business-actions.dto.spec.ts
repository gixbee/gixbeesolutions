import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { AddOperatorDto, AddOfflineDayDto } from './business-actions.dto';

/**
 * Drives the REAL global ValidationPipe ({ whitelist:true, transform:true })
 * against the business-action DTOs to prove that every legitimate
 * business_repository.dart payload passes, malformed bodies are rejected with a
 * 400, and whitelist strips unknown fields. Mirrors the Pass-74 DTO-spec style.
 */
describe('business-actions DTOs under the real ValidationPipe', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });

  const operatorMeta = { type: 'body' as const, metatype: AddOperatorDto };
  const offlineMeta = { type: 'body' as const, metatype: AddOfflineDayDto };

  describe('AddOperatorDto', () => {
    it('accepts the client { userId, role } body and keeps both fields', async () => {
      const out = await pipe.transform({ userId: 'u9', role: 'MANAGER' }, operatorMeta);
      expect(out).toEqual({ userId: 'u9', role: 'MANAGER' });
    });

    it('accepts a body with only the required userId', async () => {
      const out = await pipe.transform({ userId: 'u9' }, operatorMeta);
      expect(out).toEqual({ userId: 'u9' });
    });

    it('strips unknown fields (whitelist)', async () => {
      const out = await pipe.transform({ userId: 'u9', hacker: 1 }, operatorMeta);
      expect(out).toEqual({ userId: 'u9' });
    });

    it('rejects a missing userId', async () => {
      await expect(pipe.transform({ role: 'MANAGER' }, operatorMeta)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('rejects an empty userId', async () => {
      await expect(pipe.transform({ userId: '' }, operatorMeta)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
  });

  describe('AddOfflineDayDto', () => {
    it('accepts an ISO-8601 date string (DateTime.toIso8601String())', async () => {
      const iso = '2026-07-01T00:00:00.000Z';
      const out = await pipe.transform({ date: iso }, offlineMeta);
      expect(out).toEqual({ date: iso });
    });

    it('accepts a plain calendar date string', async () => {
      const out = await pipe.transform({ date: '2026-07-01' }, offlineMeta);
      expect(out).toEqual({ date: '2026-07-01' });
    });

    it('rejects a non-date string', async () => {
      await expect(pipe.transform({ date: 'not-a-date' }, offlineMeta)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('rejects a missing date', async () => {
      await expect(pipe.transform({}, offlineMeta)).rejects.toBeInstanceOf(BadRequestException);
    });
  });
});
