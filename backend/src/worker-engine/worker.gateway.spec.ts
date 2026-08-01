import { WorkerGateway } from './worker.gateway';
import { WsException } from '@nestjs/websockets';

/**
 * Unit tests for the realtime WorkerGateway (socket.io).
 *
 * The gateway has three reachable behaviours, all unit-testable without a real
 * socket server by injecting a stub RedisService and hand-rolled `server` /
 * `client` doubles:
 * - handleConnection / handleDisconnect: log the client id (smoke — must not
 *   throw, must read client.id).
 * - handleLocationUpdate: ALWAYS persists the location to Redis first using the
 *   JWT userId on the socket (never body.userId); then, if a jobId is present,
 *   broadcasts 'locationUpdated' to that job's room (`job_<id>`) and NOT back
 *   to the bare sender; if jobId is absent, emits 'locationUpdated' only back
 *   to the sender (client.emit) and never touches a room.
 * - handleJoinJobRoom: joins the `job_<id>` room and returns the ack envelope
 *   `{ event: 'joined', data: ... }`.
 *
 * No database, Redis, or socket is touched — every collaborator is a jest stub.
 */

function makeRedis() {
  return {
    updateWorkerLocation: jest.fn(async () => undefined),
  };
}

function makeBookingsRepository() {
  return {
    findOne: jest.fn(async () => ({
      id: 'j1',
      customer: { id: 'c1' },
      operator: { id: 'u1' },
    })),
  };
}

/** A socket.io Server double whose `.to(room)` returns a per-room emitter. */
function makeServer() {
  const rooms: Record<string, { emit: jest.Mock }> = {};
  const to = jest.fn((room: string) => {
    rooms[room] = rooms[room] ?? { emit: jest.fn() };
    return rooms[room];
  });
  return { to, rooms } as any;
}

/** A connected-socket double with JWT identity already attached by WsJwtGuard. */
function makeClient(id = 'sock-1', userId = 'u1') {
  return {
    id,
    emit: jest.fn(),
    join: jest.fn(),
    data: { user: { userId } },
    user: { userId },
  } as any;
}

function makeGateway() {
  const redis = makeRedis();
  const bookingsRepository = makeBookingsRepository();
  const gateway = new WorkerGateway(redis as any, bookingsRepository as any);
  const server = makeServer();
  gateway.server = server;
  return { gateway, redis, bookingsRepository, server };
}

describe('WorkerGateway', () => {
  describe('handleConnection / handleDisconnect', () => {
    it('reads the client id without throwing on connect', () => {
      const { gateway } = makeGateway();
      const client = makeClient('abc');
      const spy = jest
        .spyOn(console, 'log')
        .mockImplementation(() => undefined);
      expect(() => gateway.handleConnection(client)).not.toThrow();
      expect(spy).toHaveBeenCalledWith('Client connected: abc');
      spy.mockRestore();
    });

    it('reads the client id without throwing on disconnect', () => {
      const { gateway } = makeGateway();
      const client = makeClient('xyz');
      const spy = jest
        .spyOn(console, 'log')
        .mockImplementation(() => undefined);
      expect(() => gateway.handleDisconnect(client)).not.toThrow();
      expect(spy).toHaveBeenCalledWith('Client disconnected: xyz');
      spy.mockRestore();
    });
  });

  describe('handleLocationUpdate', () => {
    it('persists the location to Redis before any broadcast', async () => {
      const { gateway, redis, server } = makeGateway();
      const client = makeClient('sock-1', 'u1');
      await gateway.handleLocationUpdate(
        { userId: 'u1', lat: 12.9, lng: 77.6, jobId: 'j1' },
        client,
      );
      expect(redis.updateWorkerLocation).toHaveBeenCalledWith('u1', 12.9, 77.6);
      // persisted regardless of routing path
      expect(redis.updateWorkerLocation).toHaveBeenCalledTimes(1);
      void server;
    });

    it('ignores a spoofed body.userId and uses the JWT identity', async () => {
      const { gateway, redis, bookingsRepository, server } = makeGateway();
      bookingsRepository.findOne.mockResolvedValueOnce({
        id: 'j1',
        customer: { id: 'c1' },
        operator: { id: 'real-worker' },
      });
      const client = makeClient('sock-1', 'real-worker');
      await gateway.handleLocationUpdate(
        { userId: 'victim-worker', lat: 12.9, lng: 77.6, jobId: 'j1' },
        client,
      );
      expect(redis.updateWorkerLocation).toHaveBeenCalledWith(
        'real-worker',
        12.9,
        77.6,
      );
      const roomEmit = server.rooms['job_j1'].emit;
      const [, payload] = roomEmit.mock.calls[0];
      expect(payload.userId).toBe('real-worker');
    });

    it('rejects when the socket has no JWT user', async () => {
      const { gateway } = makeGateway();
      const client = makeClient();
      client.data = {};
      client.user = undefined;
      await expect(
        gateway.handleLocationUpdate({ lat: 1, lng: 2 }, client),
      ).rejects.toBeInstanceOf(WsException);
    });

    it('rejects job-room GPS from a user who is not the assigned operator', async () => {
      const { gateway, server } = makeGateway();
      const client = makeClient('sock-1', 'attacker');
      await expect(
        gateway.handleLocationUpdate(
          { lat: 12.9, lng: 77.6, jobId: 'j1' },
          client,
        ),
      ).rejects.toThrow('Forbidden');
      expect(server.to).not.toHaveBeenCalled();
    });

    it('broadcasts only to the job room when a jobId is given', async () => {
      const { gateway, server } = makeGateway();
      const client = makeClient('sock-1', 'u1');
      await gateway.handleLocationUpdate(
        { userId: 'u1', lat: 12.9, lng: 77.6, jobId: 'j1' },
        client,
      );
      expect(server.to).toHaveBeenCalledWith('job_j1');
      const roomEmit = server.rooms['job_j1'].emit;
      expect(roomEmit).toHaveBeenCalledTimes(1);
      const [event, payload] = roomEmit.mock.calls[0];
      expect(event).toBe('locationUpdated');
      expect(payload).toMatchObject({ userId: 'u1', lat: 12.9, lng: 77.6 });
      expect(typeof payload.timestamp).toBe('string');
      // must NOT also echo to the bare sender
      expect(client.emit).not.toHaveBeenCalled();
    });

    it('echoes only back to the sender when no jobId is given', async () => {
      const { gateway, server } = makeGateway();
      const client = makeClient('sock-1', 'u2');
      await gateway.handleLocationUpdate(
        { userId: 'u2', lat: 1.1, lng: 2.2 },
        client,
      );
      expect(client.emit).toHaveBeenCalledTimes(1);
      const [event, payload] = client.emit.mock.calls[0];
      expect(event).toBe('locationUpdated');
      expect(payload).toMatchObject({ userId: 'u2', lat: 1.1, lng: 2.2 });
      expect(typeof payload.timestamp).toBe('string');
      // no room fan-out on the fallback path
      expect(server.to).not.toHaveBeenCalled();
    });

    it('treats an empty-string jobId as absent (falls back to sender)', async () => {
      const { gateway, server } = makeGateway();
      const client = makeClient('sock-1', 'u3');
      await gateway.handleLocationUpdate(
        { userId: 'u3', lat: 0, lng: 0, jobId: '' },
        client,
      );
      expect(server.to).not.toHaveBeenCalled();
      expect(client.emit).toHaveBeenCalledTimes(1);
    });
  });

  describe('handleJoinJobRoom', () => {
    it('allows a booking participant to join the namespaced room', async () => {
      const { gateway } = makeGateway();
      const client = makeClient('sock-1', 'c1');
      const ack = await gateway.handleJoinJobRoom({ jobId: 'j1' }, client);
      expect(client.join).toHaveBeenCalledWith('job_j1');
      expect(ack).toEqual({ event: 'joined', data: 'Joined room job_j1' });
    });

    it('rejects an authenticated non-participant', async () => {
      const { gateway } = makeGateway();
      const client = makeClient('sock-1', 'attacker');
      await expect(
        gateway.handleJoinJobRoom({ jobId: 'j1' }, client),
      ).rejects.toThrow('Forbidden');
      expect(client.join).not.toHaveBeenCalled();
    });

    it('rejects a socket without an authenticated JWT user', async () => {
      const { gateway } = makeGateway();
      const client = makeClient();
      client.data = {};
      client.user = undefined;
      await expect(
        gateway.handleJoinJobRoom({ jobId: 'j1' }, client),
      ).rejects.toThrow('Unauthorized');
      expect(client.join).not.toHaveBeenCalled();
    });
  });

  describe('handleLeaveJobRoom', () => {
    it('leaves the namespaced job room', () => {
      const { gateway } = makeGateway();
      const client = { ...makeClient(), leave: jest.fn() };
      const ack = gateway.handleLeaveJobRoom({ jobId: 'j9' }, client);
      expect(client.leave).toHaveBeenCalledWith('job_j9');
      expect(ack).toEqual({ event: 'left', data: 'Left room job_j9' });
    });
  });
});
