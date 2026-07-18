import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { SendTestNotificationDto } from './send-test-notification.dto';

// Exercises the REAL global ValidationPipe (same options as main.ts) against the
// PUBLIC POST /notifications/test diagnostic DTO. No production client calls this
// route, so requiring fcmToken is safe; title/message stay optional (the
// controller defaults them) and data is free-form.
describe('SendTestNotificationDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const meta = { type: 'body', metatype: SendTestNotificationDto, data: '' } as any;
  const transform = (body: any) => pipe.transform(body, meta);

  it('accepts a full payload { fcmToken, title, message, data }', async () => {
    const out = await transform({
      fcmToken: 'tok-123',
      title: 'Hi',
      message: 'Body text',
      data: { type: 'test' },
    });
    expect(out).toBeInstanceOf(SendTestNotificationDto);
    expect(out.fcmToken).toBe('tok-123');
    expect(out.data).toEqual({ type: 'test' });
  });

  it('accepts a minimal payload (only fcmToken)', async () => {
    const out = await transform({ fcmToken: 'tok-123' });
    expect(out.fcmToken).toBe('tok-123');
    expect(out.title).toBeUndefined();
    expect(out.message).toBeUndefined();
  });

  it('strips unknown fields (whitelist)', async () => {
    const out = await transform({ fcmToken: 'tok-123', priority: 'high' });
    expect((out as any).priority).toBeUndefined();
  });

  it('rejects a missing fcmToken', async () => {
    await expect(transform({ title: 'Hi' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects an empty-string fcmToken', async () => {
    await expect(transform({ fcmToken: '' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string title', async () => {
    await expect(
      transform({ fcmToken: 'tok-123', title: 42 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
