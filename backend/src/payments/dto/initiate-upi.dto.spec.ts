import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { InitiateUpiDto } from './initiate-upi.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// POST /payments/upi/initiate DTO. The only client caller
// (payment_repository.dart) always sends { amount } and optionally { bookingId }.
describe('InitiateUpiDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: InitiateUpiDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts the full client payload { amount, bookingId }', async () => {
    const out = await transform({ amount: 499.5, bookingId: 'bk-1' });
    expect(out).toBeInstanceOf(InitiateUpiDto);
    expect(out.amount).toBe(499.5);
    expect(out.bookingId).toBe('bk-1');
  });

  it('accepts the minimal payload { amount } (no bookingId)', async () => {
    const out = await transform({ amount: 100 });
    expect(out.amount).toBe(100);
    expect(out.bookingId).toBeUndefined();
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({ amount: 100, currency: 'INR' });
    expect((out as any).currency).toBeUndefined();
  });

  it('rejects a non-numeric amount', async () => {
    await expect(transform({ amount: '100' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string bookingId', async () => {
    await expect(
      transform({ amount: 100, bookingId: 123 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
