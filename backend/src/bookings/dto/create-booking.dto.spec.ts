import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { CreateBookingDto } from './create-booking.dto';
import { BookingType } from '../booking.entity';

// Exercises the REAL global ValidationPipe (same options as main.ts) against
// CreateBookingDto so we prove the pipe now enforces input — and, just as
// important, that it does NOT reject either legitimate client call path.
describe('CreateBookingDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateBookingDto, data: '' } as any;

  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the scheduled/package path (no lat/lng/type)', async () => {
    const out = await transform({
      workerId: 'w1',
      scheduledAt: '2026-06-20T10:00:00.000Z',
      amount: 500,
      serviceLocation: '12 MG Road',
      description: 'Need a deep clean',
      skill: 'CLEANING',
      paymentMethod: 'WALLET',
    });
    expect(out).toBeInstanceOf(CreateBookingDto);
    expect(out.workerId).toBe('w1');
    expect(out.serviceLat).toBeUndefined();
    expect(out.type).toBeUndefined();
    expect(out.description).toBe('Need a deep clean');
  });

  it('accepts the instant path (lat/lng/type/onSiteContact)', async () => {
    const out = await transform({
      workerId: 'w2',
      skill: 'PLUMBING',
      serviceLocation: 'Sector 5',
      serviceLat: 12.97,
      serviceLng: 77.59,
      amount: 300,
      scheduledAt: '2026-06-20T10:00:00.000Z',
      type: 'INSTANT',
      onSiteContact: { name: 'Anu', relation: 'Self', phone: '9999999999' },
      paymentMethod: 'WALLET',
    });
    expect(out.type).toBe(BookingType.INSTANT);
    expect(out.serviceLat).toBe(12.97);
    expect(out.onSiteContact?.name).toBe('Anu');
  });

  it('strips unknown fields (whitelist) but keeps required ones', async () => {
    const out = await transform({
      workerId: 'w3',
      serviceLocation: 'X',
      scheduledAt: '2026-06-20T10:00:00.000Z',
      amount: 100,
      hackerField: 'DROP TABLE bookings;',
    });
    expect((out as any).hackerField).toBeUndefined();
    expect(out.workerId).toBe('w3');
  });

  it('rejects a missing workerId', async () => {
    await expect(
      transform({ serviceLocation: 'X', scheduledAt: 'now', amount: 100 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-numeric amount', async () => {
    await expect(
      transform({
        workerId: 'w',
        serviceLocation: 'X',
        scheduledAt: 'now',
        amount: 'free',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an invalid booking type', async () => {
    await expect(
      transform({
        workerId: 'w',
        serviceLocation: 'X',
        scheduledAt: 'now',
        amount: 100,
        type: 'TELEPORT',
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty serviceLocation', async () => {
    await expect(
      transform({
        workerId: 'w',
        serviceLocation: '',
        scheduledAt: 'now',
        amount: 100,
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
