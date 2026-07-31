import { ValidationPipe, BadRequestException } from '@nestjs/common';
import { SendMessageDto } from './send-message.dto';

// Drives the REAL global ValidationPipe (same options as main.ts) against
// SendMessageDto — proving the POST /messages route now enforces input shape
// AND that it does NOT reject the legitimate Flutter client payload
// (chat_repository.sendMessage: { recipientId, body, bookingId? }).
describe('SendMessageDto validation', () => {
  const pipe = new ValidationPipe({ whitelist: true, transform: true });
  const transform = (body: any) =>
    pipe.transform(body, {
      type: 'body',
      metatype: SendMessageDto,
      data: '',
    } as any);

  it('accepts the real client payload with bookingId', async () => {
    const out = await transform({
      recipientId: 'user-42',
      body: 'On my way!',
      bookingId: 'booking-7',
    });
    expect(out).toBeInstanceOf(SendMessageDto);
    expect(out.recipientId).toBe('user-42');
    expect(out.body).toBe('On my way!');
    expect(out.bookingId).toBe('booking-7');
  });

  it('accepts the client payload without bookingId (optional)', async () => {
    const out = await transform({ recipientId: 'user-42', body: 'Hi' });
    expect(out.recipientId).toBe('user-42');
    expect(out.body).toBe('Hi');
    expect(out.bookingId).toBeUndefined();
  });

  it('strips unknown fields (whitelist) but keeps declared ones', async () => {
    const out = await transform({
      recipientId: 'user-42',
      body: 'Hi',
      senderId: 'spoofed', // server sets sender from JWT — must not be settable
      isRead: true,
    });
    expect(out.senderId).toBeUndefined();
    expect(out.isRead).toBeUndefined();
    expect(out.recipientId).toBe('user-42');
  });

  it('rejects a missing recipientId', async () => {
    await expect(transform({ body: 'Hi' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects an empty recipientId', async () => {
    await expect(
      transform({ recipientId: '', body: 'Hi' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a missing body', async () => {
    await expect(transform({ recipientId: 'user-42' })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('rejects an empty body', async () => {
    await expect(
      transform({ recipientId: 'user-42', body: '' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string body', async () => {
    await expect(
      transform({ recipientId: 'user-42', body: 123 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-string bookingId when present', async () => {
    await expect(
      transform({ recipientId: 'user-42', body: 'Hi', bookingId: 99 }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
