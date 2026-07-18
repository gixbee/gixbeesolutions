import { ValidationPipe, BadRequestException } from '@nestjs/common';
import {
  UpdateBookingStatusDto,
  CancelBookingDto,
  ConfirmOtpDto,
  SubmitRatingDto,
  ReportDisputeDto,
} from './booking-actions.dto';
import { BookingStatus } from '../booking.entity';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// single-prop booking action DTOs — proving the pipe now enforces these bodies
// while never rejecting the legitimate client call shapes.
describe('booking action DTO validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const transform = (metatype: any) => (body: any) =>
    pipe.transform(body, { type: 'body', metatype, data: '' } as any);

  describe('UpdateBookingStatusDto', () => {
    const t = transform(UpdateBookingStatusDto);

    it('accepts a valid enum status', async () => {
      const out = await t({ status: 'COMPLETED' });
      expect(out).toBeInstanceOf(UpdateBookingStatusDto);
      expect(out.status).toBe(BookingStatus.COMPLETED);
    });

    it('strips unknown fields', async () => {
      const out = await t({ status: 'ACCEPTED', hacker: 'x' });
      expect((out as any).hacker).toBeUndefined();
    });

    it('rejects a bogus status', async () => {
      await expect(t({ status: 'TELEPORTED' })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a missing status', async () => {
      await expect(t({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('CancelBookingDto', () => {
    const t = transform(CancelBookingDto);

    it('accepts a reason (the client always sends one)', async () => {
      const out = await t({ reason: 'Changed my mind' });
      expect(out.reason).toBe('Changed my mind');
    });

    it('accepts an omitted reason (controller defaults it)', async () => {
      const out = await t({});
      expect(out.reason).toBeUndefined();
    });

    it('rejects a non-string reason', async () => {
      await expect(t({ reason: 42 })).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('ConfirmOtpDto (arrival + completion)', () => {
    const t = transform(ConfirmOtpDto);

    it('accepts a 4-digit otp string', async () => {
      const out = await t({ otp: '4821' });
      expect(out.otp).toBe('4821');
    });

    it('rejects an empty otp', async () => {
      await expect(t({ otp: '' })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a missing otp', async () => {
      await expect(t({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('SubmitRatingDto', () => {
    const t = transform(SubmitRatingDto);

    it('accepts an in-range rating', async () => {
      const out = await t({ rating: 5 });
      expect(out.rating).toBe(5);
    });

    it('rejects a below-range rating', async () => {
      await expect(t({ rating: 0 })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects an above-range rating (anti-skew)', async () => {
      await expect(t({ rating: 1000 })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a non-integer rating', async () => {
      await expect(t({ rating: 3.5 })).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('ReportDisputeDto', () => {
    const t = transform(ReportDisputeDto);

    it('accepts a reason', async () => {
      const out = await t({ reason: 'Worker never arrived' });
      expect(out.reason).toBe('Worker never arrived');
    });

    it('rejects an empty reason (required)', async () => {
      await expect(t({ reason: '' })).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a missing reason', async () => {
      await expect(t({})).rejects.toBeInstanceOf(BadRequestException);
    });
  });
});
