import { NestFactory, Reflector } from '@nestjs/core';
import { AppModule } from './app.module';
import { ClassSerializerInterceptor, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { RedisIoAdapter } from './redis/redis-io.adapter';

/**
 * SECURITY FIX — refuse to start production with development secrets.
 *
 * The repo's local .env ships weak placeholders (JWT_SECRET=super-secret-key…,
 * ADMIN_USERNAME/PASSWORD=admin). A JWT secret an attacker knows means they can
 * FORGE an { role: 'ADMIN' } token and walk straight past AdminGuard — total
 * takeover. Rather than trust a deploy checklist, fail loudly at boot.
 */
function assertProductionSecrets() {
  if (process.env.NODE_ENV !== 'production') return;

  const problems: string[] = [];
  const jwt = process.env.JWT_SECRET ?? '';
  const adminUser = process.env.ADMIN_USERNAME ?? '';
  const adminPass = process.env.ADMIN_PASSWORD ?? '';

  const WEAK_JWT = ['super-secret-key-for-gixbee', 'secret', 'changeme', ''];
  if (WEAK_JWT.includes(jwt) || jwt.length < 32) {
    problems.push('JWT_SECRET is missing, default, or shorter than 32 chars');
  }
  if (!adminUser || adminUser === 'admin') {
    problems.push('ADMIN_USERNAME is missing or the default "admin"');
  }
  if (!adminPass || adminPass === 'admin' || adminPass.length < 12) {
    problems.push('ADMIN_PASSWORD is missing, default, or shorter than 12 chars');
  }
  if (process.env.ALLOW_OTP_ECHO === 'true') {
    problems.push('ALLOW_OTP_ECHO=true would return login OTPs to callers');
  }

  if (problems.length > 0) {
    console.error('\n[FATAL] Refusing to start in production with insecure config:');
    for (const p of problems) console.error(`  - ${p}`);
    console.error('Rotate these values and restart.\n');
    process.exit(1);
  }
}

async function bootstrap() {
  assertProductionSecrets();

  const app = await NestFactory.create(AppModule);

  // Multi-instance Socket.IO fan-out via Redis. Fail-soft: if Redis is down
  // at boot we keep the default in-memory adapter (fine for single-process dev).
  const redisIoAdapter = new RedisIoAdapter(app, app.get(ConfigService));
  await redisIoAdapter.connectToRedis();
  app.useWebSocketAdapter(redisIoAdapter);

  // CORS for the Flutter web app. Tokens ride the Authorization header (not
  // cookies), so `credentials` is deliberately NOT enabled.
  app.enableCors({
    origin: '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
  });

  app.useGlobalPipes(new ValidationPipe({
    whitelist: true,
    transform: true,
  }));

  // Strip @Exclude'd entity fields (User.fcmToken/walletBalance) from every
  // response — relation-loaded users no longer leak private data.
  app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));

  // Consistent error envelope + no stack-trace leakage on 5xx
  app.useGlobalFilters(new AllExceptionsFilter());

  const port = process.env.PORT ?? 3000;
  await app.listen(port, '0.0.0.0');
  console.log(`🚀 Gixbee Backend running on http://localhost:${port}`);
}
bootstrap();
