import { MessagesController } from './messages.controller';

/**
 * Unit tests for the MessagesController HTTP layer — a thin delegation over
 * MessagesService. Instantiated directly with a jest-mock service (matching this
 * repo's controller-spec style — no Nest TestingModule, no DB/network). Asserts
 * the JWT `req.user.userId` injection on every route, URL `:userId` forwarding on
 * the thread read, and the send() body→positional-arg mapping (recipientId, body,
 * optional bookingId).
 */

function makeController() {
  const messagesService: any = {
    getConversations: jest.fn(async () => [{ partnerId: 'p1' }]),
    getThread: jest.fn(async () => [{ id: 'm1' }, { id: 'm2' }]),
    send: jest.fn(async () => ({ id: 'm3' })),
  };
  const controller = new MessagesController(messagesService);
  return { controller, messagesService };
}

const req = { user: { userId: 'me-1' } };

describe('MessagesController.conversations', () => {
  it('delegates to getConversations with the authed userId', async () => {
    const { controller, messagesService } = makeController();
    const res = await controller.conversations(req);
    expect(messagesService.getConversations).toHaveBeenCalledWith('me-1');
    expect(res).toEqual([{ partnerId: 'p1' }]);
  });
});

describe('MessagesController.thread', () => {
  it('forwards the authed userId and the URL :userId to getThread', async () => {
    const { controller, messagesService } = makeController();
    const res = await controller.thread(req, 'other-9');
    expect(messagesService.getThread).toHaveBeenCalledWith('me-1', 'other-9');
    expect(res).toEqual([{ id: 'm1' }, { id: 'm2' }]);
  });
});

describe('MessagesController.send', () => {
  it('maps the body to positional args including bookingId when present', async () => {
    const { controller, messagesService } = makeController();
    const res = await controller.send(req, {
      recipientId: 'r-2',
      body: 'hello',
      bookingId: 'b-7',
    });
    expect(messagesService.send).toHaveBeenCalledWith('me-1', 'r-2', 'hello', 'b-7');
    expect(res).toEqual({ id: 'm3' });
  });

  it('passes undefined bookingId through when omitted', async () => {
    const { controller, messagesService } = makeController();
    await controller.send(req, { recipientId: 'r-2', body: 'hi' });
    expect(messagesService.send).toHaveBeenCalledWith('me-1', 'r-2', 'hi', undefined);
  });
});
