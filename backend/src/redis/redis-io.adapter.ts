import { INestApplication, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { createClient, RedisClientType } from 'redis';
import { ServerOptions } from 'socket.io';
import { buildRedisUrl } from './redis-url';

/**
 * Socket.IO Redis adapter so WebSocket rooms/events fan out across multiple
 * Nest backend instances (~1k concurrent live workers / multi-replica deploy).
 *
 * If Redis is unreachable at boot, connectToRedis() logs a warning and leaves
 * the default in-memory adapter in place — useful for local dev without Redis.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor: ReturnType<typeof createAdapter> | null = null;
  private pubClient: RedisClientType | null = null;
  private subClient: RedisClientType | null = null;

  constructor(
    app: INestApplication,
    private readonly configService: ConfigService,
  ) {
    super(app);
  }

  async connectToRedis(): Promise<boolean> {
    const url = buildRedisUrl(this.configService);
    const socket = {
      reconnectStrategy: (retries: number) => Math.min(retries * 500, 30_000),
    };

    try {
      this.pubClient = createClient({ url, socket }) as RedisClientType;
      this.subClient = this.pubClient.duplicate();

      this.pubClient.on('error', (err) => {
        this.logger.warn(`Redis pub client error: ${err?.message ?? err}`);
      });
      this.subClient.on('error', (err) => {
        this.logger.warn(`Redis sub client error: ${err?.message ?? err}`);
      });

      await Promise.all([this.pubClient.connect(), this.subClient.connect()]);
      this.adapterConstructor = createAdapter(this.pubClient, this.subClient);
      this.logger.log('Socket.IO Redis adapter connected');
      return true;
    } catch (err: any) {
      this.logger.warn(
        `Socket.IO Redis adapter unavailable (${err?.message ?? err}) — using in-memory adapter`,
      );
      await this.disconnectQuietly();
      this.adapterConstructor = null;
      return false;
    }
  }

  createIOServer(port: number, options?: ServerOptions) {
    const server = super.createIOServer(port, options);
    if (this.adapterConstructor) {
      server.adapter(this.adapterConstructor);
    }
    return server;
  }

  private async disconnectQuietly(): Promise<void> {
    for (const client of [this.pubClient, this.subClient]) {
      if (!client) continue;
      try {
        if (client.isOpen) await client.quit();
      } catch {
        /* ignore */
      }
    }
    this.pubClient = null;
    this.subClient = null;
  }
}
