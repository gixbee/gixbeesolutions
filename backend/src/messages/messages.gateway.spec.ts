import { MessagesGateway } from './messages.gateway';

/**
 * Unit tests for the realtime MessagesGateway (socket.io).
 *
 * The gateway has two reachable behaviours, both unit-testable without a real
 * socket server by hand-rolling `server` / `client` doubles (same approach as
 * worker.gateway.spec.ts):
 * - handleJoinUserRoom: joins the caller's personal room `user_<id>` ONLY when a
 *   non-empty userId is supplied, and always returns the ack envelope
 *   `{ event: 'joinedUserRoom', data: <userId> }` (data is undefined when absent).
 * - emitToUser: pushes a `new_message` payload to `user_<recipientId>`; the
 *   optional-chaining on `this.server?` must make it a no-op (not throw) when the
 *   server has not been wired yet.
 *
 * No socket, database, or network is touched — every collaborator is a jest stub.
 */

/** A socket.io Server double whose `.to(room)` returns a per-room emitter. */
function makeServer() {
  const rooms: Record<string, { emit: jest.Mock }> = {};
  const to = jest.fn((room: string) => {
    rooms[room] = rooms[room] ?? { emit: jest.fn() };
    return rooms[room];
  });
  return { to, rooms } as any;
}

/** A connected-socket double. */
function makeClient(id = 'sock-1') {
  return {
    id,
    emit: jest.fn(),
    join: jest.fn(),
  } as any;
}

function makeGateway() {
  const gateway = new MessagesGateway();
  const server = makeServer();
  gateway.server = server;
  return { gateway, server };
}

describe('MessagesGateway', () => {
  describe('handleJoinUserRoom', () => {
    it('joins the namespaced user room and returns the ack envelope', () => {
      const { gateway } = makeGateway();
      const client = makeClient();
      const ack = gateway.handleJoinUserRoom({ userId: 'u9' }, client);
      expect(client.join).toHaveBeenCalledWith('user_u9');
      expect(ack).toEqual({ event: 'joinedUserRoom', data: 'u9' });
    });

    it('does not join a room when userId is missing but still acks', () => {
      const { gateway } = makeGateway();
      const client = makeClient();
      const ack = gateway.handleJoinUserRoom({} as any, client);
      expect(client.join).not.toHaveBeenCalled();
      expect(ack).toEqual({ event: 'joinedUserRoom', data: undefined });
    });

    it('treats an empty-string userId as absent (no join)', () => {
      const { gateway } = makeGateway();
      const client = makeClient();
      const ack = gateway.handleJoinUserRoom({ userId: '' }, client);
      expect(client.join).not.toHaveBeenCalled();
      expect(ack).toEqual({ event: 'joinedUserRoom', data: '' });
    });
  });

  describe('emitToUser', () => {
    it('pushes a new_message payload to the recipient personal room', () => {
      const { gateway, server } = makeGateway();
      const payload = { id: 'm1', body: 'hi' };
      gateway.emitToUser('u1', payload);
      expect(server.to).toHaveBeenCalledWith('user_u1');
      const roomEmit = server.rooms['user_u1'].emit;
      expect(roomEmit).toHaveBeenCalledTimes(1);
      expect(roomEmit).toHaveBeenCalledWith('new_message', payload);
    });

    it('is a safe no-op when the server has not been wired yet', () => {
      const gateway = new MessagesGateway();
      // server intentionally left undefined
      expect(() => gateway.emitToUser('u2', { body: 'x' })).not.toThrow();
    });
  });
});
