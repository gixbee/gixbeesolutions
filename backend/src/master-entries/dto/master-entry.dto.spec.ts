import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { CreateMasterEntryDto, UpdateMasterEntryDto } from './master-entry.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// admin-only master-entries write DTOs. Mirrors the super-admin Angular client:
// CREATE always sends type+label+value (+optional icon/category/isActive); the
// quick Enable/Disable toggle PATCHes a body of ONLY { isActive }, so the update
// DTO must accept that single-field body and strip the id/timestamps the edit
// modal echoes back.
describe('CreateMasterEntryDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateMasterEntryDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts a full CATEGORY payload', async () => {
    const out = await transform({
      type: 'CATEGORY',
      label: 'Plumbing',
      value: 'plumbing',
      icon: '🔧',
      category: 'home',
      isActive: true,
    });
    expect(out).toBeInstanceOf(CreateMasterEntryDto);
    expect(out.type).toBe('CATEGORY');
    expect(out.value).toBe('plumbing');
  });

  it('accepts a BANNER payload (value is the uploaded image URL)', async () => {
    const out = await transform({
      type: 'BANNER',
      label: 'Summer sale banner',
      value: '/uploads/summer.png',
      category: '/offers/summer',
      isActive: true,
    });
    expect(out.icon).toBeUndefined();
    expect(out.value).toBe('/uploads/summer.png');
  });

  it('strips unknown fields (whitelist) — e.g. echoed id/createdAt', async () => {
    const out = await transform({
      type: 'SERVICE',
      label: 'Deep clean',
      value: 'deep_clean',
      id: 'should-be-stripped',
      createdAt: '2026-01-01',
    });
    expect((out as any).id).toBeUndefined();
    expect((out as any).createdAt).toBeUndefined();
  });

  it('rejects a missing required field (no value)', async () => {
    await expect(
      transform({ type: 'CATEGORY', label: 'Plumbing' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty-string label', async () => {
    await expect(
      transform({ type: 'CATEGORY', label: '', value: 'x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an invalid type enum', async () => {
    await expect(
      transform({ type: 'NOT_A_TYPE', label: 'x', value: 'x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-boolean isActive', async () => {
    await expect(
      transform({ type: 'CATEGORY', label: 'x', value: 'x', isActive: 'yes' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('UpdateMasterEntryDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: UpdateMasterEntryDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the toggle body of ONLY { isActive }', async () => {
    const out = await transform({ isActive: false });
    expect(out).toBeInstanceOf(UpdateMasterEntryDto);
    expect(out.isActive).toBe(false);
    expect(out.label).toBeUndefined();
  });

  it('accepts a partial edit (label + value only)', async () => {
    const out = await transform({ label: 'Renamed', value: 'renamed' });
    expect(out.label).toBe('Renamed');
  });

  it('accepts an empty body (no-op partial)', async () => {
    const out = await transform({});
    expect(out).toBeInstanceOf(UpdateMasterEntryDto);
  });

  it('strips id/createdAt/updatedAt the edit modal echoes back', async () => {
    const out = await transform({
      isActive: true,
      id: 'keep-the-pk-out',
      createdAt: '2026-01-01',
      updatedAt: '2026-02-02',
    });
    expect((out as any).id).toBeUndefined();
    expect((out as any).createdAt).toBeUndefined();
    expect((out as any).updatedAt).toBeUndefined();
  });

  it('rejects an empty-string value when value IS present', async () => {
    await expect(
      transform({ value: '' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an invalid type enum when present', async () => {
    await expect(
      transform({ type: 'BOGUS' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
