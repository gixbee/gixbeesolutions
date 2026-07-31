import { NotFoundException } from '@nestjs/common';
import { MessagesService } from './messages.service';

/**
 * Unit tests for the direct-messaging module:
 * - send: NotFound when the recipient is unknown; otherwise trims the body,
 *   persists with isRead=false, reloads with relations so the DTO carries
 *   sender/recipient ids, and pushes a 'new_message' event to the recipient's
 *   socket room.
 * - getThread: returns both directions oldest-first and marks the inbound
 *   unread messages read (fires the bulk UPDATE).
 * - getConversations: collapses the message list to one entry per partner
 *   (newest activity first), counts only inbound-unread messages, and falls
 *   back to 'Gixbee user' for a blank name.
 *
 * The repos use a chainable createQueryBuilder mock + a stub gateway so each
 * branch toggles deterministically; no database or socket is touched.
 */
function chainBuilder(rows: any[]) {
  const qb: any = {
    leftJoinAndSelect: jest.fn(() => qb),
    where: jest.fn(() => qb),
    orWhere: jest.fn(() => qb),
    orderBy: jest.fn(() => qb),
    update: jest.fn(() => qb),
    set: jest.fn(() => qb),
    getMany: jest.fn(async () => rows),
    execute: jest.fn(async () => ({ affected: rows.length })),
  };
  return qb;
}

function makeService(
  opts: { recipient?: any; reloaded?: any; rows?: any[] } = {},
) {
  const saved: any[] = [];
  const qb = chainBuilder(opts.rows ?? []);

  const messagesRepo: any = {
    create: jest.fn((dto: any) => ({ id: 'msg-new', ...dto })),
    save: jest.fn(async (m: any) => {
      saved.push(m);
      return m;
    }),
    findOne: jest.fn(async () => opts.reloaded ?? null),
    createQueryBuilder: jest.fn(() => qb),
  };

  const usersRepo: any = {
    findOne: jest.fn(async () => opts.recipient ?? null),
  };

  const gateway: any = { emitToUser: jest.fn() };

  const service = new MessagesService(messagesRepo, usersRepo, gateway);
  return { service, messagesRepo, usersRepo, gateway, saved, qb };
}

describe('MessagesService.send', () => {
  it('throws NotFound when the recipient does not exist', async () => {
    const { service, gateway } = makeService({ recipient: null });

    await expect(service.send('s1', 'ghost', 'hi')).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(gateway.emitToUser).not.toHaveBeenCalled();
  });

  it('trims the body, persists isRead=false, and emits to the recipient', async () => {
    const reloaded = {
      id: 'msg-new',
      body: 'hello',
      bookingId: null,
      isRead: false,
      createdAt: new Date('2026-06-18T10:00:00Z'),
      sender: { id: 's1' },
      recipient: { id: 'r1' },
    };
    const { service, messagesRepo, gateway, saved } = makeService({
      recipient: { id: 'r1' },
      reloaded,
    });

    const dto = await service.send('s1', 'r1', '  hello  ', 'booking-9');

    // body trimmed + isRead false at create time
    expect(messagesRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({
        body: 'hello',
        isRead: false,
        bookingId: 'booking-9',
      }),
    );
    expect(saved).toHaveLength(1);
    // DTO carries the reloaded sender/recipient ids
    expect(dto.senderId).toBe('s1');
    expect(dto.recipientId).toBe('r1');
    // gateway gets a new_message event addressed to the recipient
    expect(gateway.emitToUser).toHaveBeenCalledWith(
      'r1',
      expect.objectContaining({
        _event: 'new_message',
        senderId: 's1',
        recipientId: 'r1',
      }),
    );
  });

  it('defaults bookingId to null when not supplied', async () => {
    const reloaded = {
      id: 'msg-new',
      body: 'yo',
      bookingId: null,
      isRead: false,
      createdAt: new Date(),
      sender: { id: 's1' },
      recipient: { id: 'r1' },
    };
    const { service, messagesRepo } = makeService({
      recipient: { id: 'r1' },
      reloaded,
    });

    await service.send('s1', 'r1', 'yo');

    expect(messagesRepo.create).toHaveBeenCalledWith(
      expect.objectContaining({ bookingId: null }),
    );
  });
});

describe('MessagesService.getThread', () => {
  it('returns messages oldest-first and fires the mark-read update', async () => {
    const rows = [
      {
        id: 'm1',
        body: 'first',
        bookingId: null,
        isRead: true,
        createdAt: new Date('2026-06-18T09:00:00Z'),
        sender: { id: 'other' },
        recipient: { id: 'me' },
      },
      {
        id: 'm2',
        body: 'second',
        bookingId: null,
        isRead: false,
        createdAt: new Date('2026-06-18T09:05:00Z'),
        sender: { id: 'me' },
        recipient: { id: 'other' },
      },
    ];
    const { service, qb } = makeService({ rows });

    const result = await service.getThread('me', 'other');

    expect(result.map((m) => m.id)).toEqual(['m1', 'm2']);
    expect(result[0].senderId).toBe('other');
    // the bulk mark-read UPDATE ran
    expect(qb.update).toHaveBeenCalled();
    expect(qb.execute).toHaveBeenCalled();
  });
});

describe('MessagesService.getConversations', () => {
  it('collapses to one entry per partner and counts inbound-unread only', async () => {
    // newest first (service orders DESC); partner is the non-me side
    const rows = [
      {
        id: 'm3',
        body: 'latest from other',
        isRead: false,
        createdAt: new Date('2026-06-18T12:00:00Z'),
        sender: { id: 'other', name: 'Other', phoneNumber: '900' },
        recipient: { id: 'me' },
      },
      {
        id: 'm2',
        body: 'older from other',
        isRead: false,
        createdAt: new Date('2026-06-18T11:00:00Z'),
        sender: { id: 'other', name: 'Other', phoneNumber: '900' },
        recipient: { id: 'me' },
      },
      {
        id: 'm1',
        body: 'sent by me',
        isRead: true,
        createdAt: new Date('2026-06-18T10:00:00Z'),
        sender: { id: 'me' },
        recipient: { id: 'other', name: 'Other', phoneNumber: '900' },
      },
    ];
    const { service } = makeService({ rows });

    const convos = await service.getConversations('me');

    expect(convos).toHaveLength(1);
    const c = convos[0];
    expect(c.userId).toBe('other');
    // lastMessage = newest (first encountered)
    expect(c.lastMessage).toBe('latest from other');
    // two inbound unread; the message I sent does not count
    expect(c.unread).toBe(2);
  });

  it("falls back to 'Gixbee user' when the partner name is blank", async () => {
    const rows = [
      {
        id: 'm1',
        body: 'hi',
        isRead: true,
        createdAt: new Date('2026-06-18T10:00:00Z'),
        sender: { id: 'other', name: '', phoneNumber: '901' },
        recipient: { id: 'me' },
      },
    ];
    const { service } = makeService({ rows });

    const convos = await service.getConversations('me');

    expect(convos[0].name).toBe('Gixbee user');
    expect(convos[0].unread).toBe(0); // already read
  });
});
