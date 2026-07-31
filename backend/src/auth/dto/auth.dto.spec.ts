import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  RequestOtpDto,
  VerifyOtpDto,
  RefreshTokenDto,
  UpdateFcmTokenDto,
  AdminLoginDto,
} from './auth.dto';

// Proves the auth write-endpoint DTOs enforce via the real global pipe, while
// still accepting exactly what auth_repository.dart sends.
describe('Auth DTO validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const t = (metatype: any) => (body: any) =>
    pipe.transform(body, { type: 'body', metatype, data: '' } as any);

  describe('RequestOtpDto', () => {
    const run = t(RequestOtpDto);
    it('accepts a phone', async () => {
      const out = await run({ phone: '+919999999999' });
      expect(out.phone).toBe('+919999999999');
    });
    it('rejects a missing phone', async () => {
      await expect(run({})).rejects.toBeInstanceOf(BadRequestException);
    });
    it('rejects an empty phone', async () => {
      await expect(run({ phone: '' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
    it('strips unknown fields', async () => {
      const out = await run({ phone: '123', evil: 1 });
      expect(out.evil).toBeUndefined();
    });
  });

  describe('VerifyOtpDto', () => {
    const run = t(VerifyOtpDto);
    it('accepts phone + otp', async () => {
      const out = await run({ phone: '123', otp: '0000' });
      expect(out.otp).toBe('0000');
    });
    it('rejects a missing otp', async () => {
      await expect(run({ phone: '123' })).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });
  });

  describe('RefreshTokenDto', () => {
    const run = t(RefreshTokenDto);
    it('accepts a refreshToken', async () => {
      const out = await run({ refreshToken: 'abc.def.ghi' });
      expect(out.refreshToken).toBe('abc.def.ghi');
    });
    it('rejects a missing refreshToken', async () => {
      await expect(run({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('UpdateFcmTokenDto', () => {
    const run = t(UpdateFcmTokenDto);
    it('accepts the legacy fcmToken body the client sends', async () => {
      const out = await run({ fcmToken: 'tok123' });
      expect(out.fcmToken).toBe('tok123');
    });
    it('rejects a missing fcmToken', async () => {
      await expect(run({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('AdminLoginDto', () => {
    const run = t(AdminLoginDto);
    it('accepts username + password', async () => {
      const out = await run({ username: 'admin', password: 'pw' });
      expect(out.username).toBe('admin');
    });
    it('accepts an empty body (controller coalesces to 401, not 400)', async () => {
      const out = await run({});
      expect(out.username).toBeUndefined();
    });
  });
});
