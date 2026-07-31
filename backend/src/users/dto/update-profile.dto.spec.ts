import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { UpdateUserProfileDto } from './update-profile.dto';
import { UserRole } from '../user.entity';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// PATCH /admin-user-list/:id DTO. All three real client payload shapes (traced
// from the Flutter app) must pass; whitelist must strip unknown fields; type/enum
// validation must reject malformed values.
describe('UpdateUserProfileDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = {
    type: 'body',
    metatype: UpdateUserProfileDto,
    data: '',
  } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the registration_screen payload { name, role, hasWorkerProfile }', async () => {
    const out = await transform({
      name: 'Asha',
      role: 'OPERATOR',
      hasWorkerProfile: true,
    });
    expect(out).toBeInstanceOf(UpdateUserProfileDto);
    expect(out.name).toBe('Asha');
    expect(out.role).toBe(UserRole.OPERATOR);
    expect(out.hasWorkerProfile).toBe(true);
  });

  it('accepts the edit_profile payload { name }', async () => {
    const out = await transform({ name: 'New Name' });
    expect(out.name).toBe('New Name');
    expect(out.role).toBeUndefined();
  });

  it('accepts the availability-toggle payload { isAvailableForWork }', async () => {
    const out = await transform({ isAvailableForWork: false });
    expect(out.isAvailableForWork).toBe(false);
  });

  it('accepts the OWNER role too', async () => {
    const out = await transform({
      name: 'Biz',
      role: 'OWNER',
      hasWorkerProfile: false,
    });
    expect(out.role).toBe(UserRole.OWNER);
  });

  it('accepts an empty patch ({})', async () => {
    const out = await transform({});
    expect(out).toBeInstanceOf(UpdateUserProfileDto);
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      name: 'Asha',
      email: 'a@b.com',
      isVerified: true,
    });
    expect(out.email).toBeUndefined();
    expect(out.isVerified).toBeUndefined();
    expect(out.name).toBe('Asha');
  });

  it('rejects a non-string name', async () => {
    await expect(transform({ name: 123 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects a non-boolean isAvailableForWork', async () => {
    await expect(
      transform({ isAvailableForWork: 'yes' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an invalid role enum value', async () => {
    await expect(transform({ role: 'SUPERUSER' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});
