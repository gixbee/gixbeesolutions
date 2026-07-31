import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { CreateBusinessDto } from './create-business.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// list-my-business write DTO. The client payload is Business.toJson()
// (lib/shared/models/business.dart): name, type, description, specialty, phone,
// address — every field declared so whitelist strips nothing. Only name + type
// are required (non-nullable columns, always sent); the rest are optional.
describe('CreateBusinessDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateBusinessDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full Business.toJson() client payload', async () => {
    const out = await transform({
      name: 'Sparkle Cleaners',
      type: 'CLEANING',
      description: 'Home & office cleaning.',
      specialty: 'Deep cleaning',
      phone: '+919900112233',
      address: '12 MG Road, Bengaluru',
    });
    expect(out).toBeInstanceOf(CreateBusinessDto);
    expect(out.name).toBe('Sparkle Cleaners');
    expect(out.type).toBe('CLEANING');
  });

  it('accepts a minimal payload (only name + type)', async () => {
    const out = await transform({ name: 'Sparkle', type: 'CLEANING' });
    expect(out.description).toBeUndefined();
    expect(out.phone).toBeUndefined();
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      name: 'Sparkle',
      type: 'CLEANING',
      status: 'APPROVED',
    });
    expect(out.status).toBeUndefined();
  });

  it('rejects a missing name', async () => {
    await expect(transform({ type: 'CLEANING' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects an empty-string type', async () => {
    await expect(
      transform({ name: 'Sparkle', type: '' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string phone', async () => {
    await expect(
      transform({ name: 'Sparkle', type: 'CLEANING', phone: 9900112233 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
