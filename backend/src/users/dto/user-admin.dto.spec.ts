import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  UpdateFcmTokenDto,
  UpdateSkillStatusDto,
  UpdateUserStatusDto,
  VerifyUserDto,
} from './user-admin.dto';
import { SkillApprovalStatus } from '../../talent/professional-skill.entity';
import { UserApprovalStatus } from '../user.entity';

/**
 * Drives the REAL global ValidationPipe ({ whitelist:true, transform:true })
 * against the admin-user-list DTOs. Confirms each caller payload
 * (super-admin-web user.service.ts) passes, bad enums / wrong types are
 * rejected with a 400, and whitelist strips unknown fields.
 */
describe('admin-user-list DTOs under the real ValidationPipe', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });

  it('UpdateFcmTokenDto accepts { token } and rejects an empty/missing token', async () => {
    const meta = { type: 'body' as const, metatype: UpdateFcmTokenDto };
    expect(await pipe.transform({ token: 'tok-1' }, meta)).toEqual({ token: 'tok-1' });
    await expect(pipe.transform({ token: '' }, meta)).rejects.toBeInstanceOf(BadRequestException);
    await expect(pipe.transform({}, meta)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('UpdateSkillStatusDto accepts a valid enum and rejects a bad one', async () => {
    const meta = { type: 'body' as const, metatype: UpdateSkillStatusDto };
    expect(
      await pipe.transform({ status: SkillApprovalStatus.APPROVED }, meta),
    ).toEqual({ status: SkillApprovalStatus.APPROVED });
    await expect(pipe.transform({ status: 'NOPE' }, meta)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('UpdateUserStatusDto accepts a valid enum and rejects a bad one', async () => {
    const meta = { type: 'body' as const, metatype: UpdateUserStatusDto };
    expect(
      await pipe.transform({ status: UserApprovalStatus.APPROVED }, meta),
    ).toEqual({ status: UserApprovalStatus.APPROVED });
    await expect(pipe.transform({ status: 'NOPE' }, meta)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('VerifyUserDto accepts a boolean and rejects a non-boolean', async () => {
    const meta = { type: 'body' as const, metatype: VerifyUserDto };
    expect(await pipe.transform({ isVerified: true }, meta)).toEqual({ isVerified: true });
    await expect(pipe.transform({ isVerified: 'yes' }, meta)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('strips unknown fields (whitelist) on a status update', async () => {
    const meta = { type: 'body' as const, metatype: UpdateUserStatusDto };
    const out = await pipe.transform(
      { status: UserApprovalStatus.APPROVED, hacker: 1 },
      meta,
    );
    expect(out).toEqual({ status: UserApprovalStatus.APPROVED });
  });
});
