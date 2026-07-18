import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { CreateRentalItemDto, RequestReservationDto } from './rentals.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// rentals DTOs so we prove the pipe now enforces input on POST /rentals and
// POST /rentals/:id/reserve, while still accepting every legitimate payload the
// controller's manual guard accepted before (the rentals flow is server-driven;
// these mirror the existing contract exactly).
describe('CreateRentalItemDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: CreateRentalItemDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full payload', async () => {
    const out = await transform({
      ownerId: 'u1',
      name: 'Power Drill',
      hourlyRate: 50,
      minHoursToRent: 2,
      description: 'Cordless 18V',
    });
    expect(out).toBeInstanceOf(CreateRentalItemDto);
    expect(out.ownerId).toBe('u1');
    expect(out.minHoursToRent).toBe(2);
  });

  it('accepts the minimal required payload (no minHoursToRent/description)', async () => {
    const out = await transform({ ownerId: 'u1', name: 'Ladder', hourlyRate: 20 });
    expect(out.minHoursToRent).toBeUndefined();
    expect(out.description).toBeUndefined();
  });

  it('strips unknown fields (whitelist) but keeps required ones', async () => {
    const out = await transform({
      ownerId: 'u1',
      name: 'Drill',
      hourlyRate: 50,
      isAdmin: true,
    });
    expect((out as any).isAdmin).toBeUndefined();
    expect(out.name).toBe('Drill');
  });

  it('rejects a missing ownerId', async () => {
    await expect(
      transform({ name: 'Drill', hourlyRate: 50 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty name', async () => {
    await expect(
      transform({ ownerId: 'u1', name: '', hourlyRate: 50 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-numeric hourlyRate', async () => {
    await expect(
      transform({ ownerId: 'u1', name: 'Drill', hourlyRate: 'free' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});

describe('RequestReservationDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: RequestReservationDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts ISO start/end strings (parsed by the controller, not the DTO)', async () => {
    const out = await transform({
      renterId: 'r1',
      startTime: '2026-06-21T09:00:00.000Z',
      endTime: '2026-06-21T12:00:00.000Z',
    });
    expect(out).toBeInstanceOf(RequestReservationDto);
    expect(out.renterId).toBe('r1');
  });

  it('rejects a missing renterId', async () => {
    await expect(
      transform({ startTime: 'a', endTime: 'b' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty startTime', async () => {
    await expect(
      transform({ renterId: 'r1', startTime: '', endTime: 'b' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
