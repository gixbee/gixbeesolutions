import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { CreateBusinessDto } from './create-business.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// list-my-business write DTO. Client payload is Business.toJson(): name, type,
// description, specialty, phone, address. Required: name, type, address
// (address maps to Business.location in the service).
describe('CreateBusinessDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateBusinessDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full Business.toJson() client payload', async () => {
    const out = await transform({
      name: 'Sparkle Cleaners',
      type: 'SERVICE',
      description: 'Home & office cleaning.',
      specialty: 'Deep cleaning',
      phone: '+919900112233',
      address: '12 MG Road, Bengaluru',
    });
    expect(out).toBeInstanceOf(CreateBusinessDto);
    expect(out.name).toBe('Sparkle Cleaners');
    expect(out.type).toBe('SERVICE');
    expect(out.address).toBe('12 MG Road, Bengaluru');
  });

  it('accepts a minimal payload (name + type + address)', async () => {
    const out = await transform({
      name: 'Sparkle',
      type: 'HIRING',
      address: 'Pune',
    });
    expect(out.description).toBeUndefined();
    expect(out.phone).toBeUndefined();
    expect(out.address).toBe('Pune');
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({
      name: 'Sparkle',
      type: 'SERVICE',
      address: 'Pune',
      status: 'APPROVED',
    });
    expect(out.status).toBeUndefined();
  });

  it('rejects a missing name', async () => {
    await expect(
      transform({ type: 'SERVICE', address: 'Pune' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a missing address', async () => {
    await expect(
      transform({ name: 'Sparkle', type: 'SERVICE' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty-string type', async () => {
    await expect(
      transform({ name: 'Sparkle', type: '', address: 'Pune' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string phone', async () => {
    await expect(
      transform({
        name: 'Sparkle',
        type: 'SERVICE',
        address: 'Pune',
        phone: 9900112233,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
