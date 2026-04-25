# Gixbee — Hosting Strategy (Free to Low Cost)

## Your stack requirements

| Service | Used for |
|---|---|
| NestJS (Node.js) | REST API, WebSockets, Bull queues |
| PostgreSQL | Primary database |
| Redis | Bull job queues, caching |
| File storage | Worker profile photos, uploads |
| Flutter | Mobile app (Android/iOS) — no server hosting needed |

---

## Recommended Setup — $0/month to start, ~$10/month at scale

```
┌─────────────────────────────────────────────────────────┐
│                    GIXBEE HOSTING MAP                   │
├─────────────────┬───────────────────────────────────────┤
│ Flutter App     │ Play Store + App Store (one-time fee) │
│ NestJS Backend  │ Railway (free tier → $5/mo)           │
│ PostgreSQL      │ Railway built-in or Supabase (free)   │
│ Redis           │ Upstash (free tier, serverless)       │
│ File Storage    │ Cloudinary (free 25GB)                │
│ Domain / SSL    │ Free on Railway / Cloudflare          │
└─────────────────┴───────────────────────────────────────┘
```

---

## Option 1 — 100% Free (development / early users)

### NestJS → Railway

**Why Railway:**
- Free $5 credit/month — enough for a small NestJS app
- Native WebSocket support (Vercel/Netlify kill long connections — not suitable for your Socket.io)
- Auto-deploy from GitHub on every push
- Built-in PostgreSQL and Redis plugins
- Zero config — detects Node.js and `start:prod` script automatically

**Deploy steps:**
```bash
# 1. Push your backend/ folder to GitHub

# 2. Go to railway.app → New Project → Deploy from GitHub repo
#    Point to the backend/ subfolder if it's a monorepo

# 3. Set environment variables in Railway dashboard (Settings → Variables):
DATABASE_URL=${{Postgres.DATABASE_URL}}   # auto-injected by Railway Postgres plugin
REDIS_URL=<upstash redis url>
JWT_SECRET=your-secret-here
FIREBASE_PROJECT_ID=...
FIREBASE_CLIENT_EMAIL=...
FIREBASE_PRIVATE_KEY=...
NODE_ENV=production
PORT=3000
```

Railway auto-detects `"start:prod": "node dist/main"` from your `package.json`.

Set the **build command** in Railway dashboard:
```
npm install && npm run build
```

---

### PostgreSQL → Railway built-in plugin

Add the PostgreSQL plugin to your Railway project in one click.
Railway auto-injects `DATABASE_URL` into your environment — no manual config needed.

Update your TypeORM config to read from `DATABASE_URL`:

```typescript
// app.module.ts
TypeOrmModule.forRootAsync({
  imports: [ConfigModule],
  useFactory: (config: ConfigService) => ({
    type: 'postgres',
    url: config.get('DATABASE_URL'),
    ssl: config.get('NODE_ENV') === 'production'
      ? { rejectUnauthorized: false }
      : false,
    entities: [__dirname + '/**/*.entity{.ts,.js}'],
    synchronize: false,           // NEVER true in production
    migrations: [__dirname + '/migrations/**/*{.ts,.js}'],
    migrationsRun: true,
  }),
  inject: [ConfigService],
}),
```

---

### Redis → Upstash (Free Tier)

**Why Upstash:**
- Free: 10,000 commands/day — enough for dev and early users
- Serverless Redis — zero idle cost, pay per request
- Works perfectly with your existing Bull queue setup

**Setup:**
1. Go to [upstash.com](https://upstash.com) → Create Database
2. Select region: **ap-south-1 (Mumbai)** — closest to India
3. Copy the `REDIS_URL` (starts with `rediss://`)

Update your Bull config:
```typescript
// app.module.ts
BullModule.forRootAsync({
  imports: [ConfigModule],
  useFactory: (config: ConfigService) => ({
    redis: config.get('REDIS_URL'),
  }),
  inject: [ConfigService],
}),
```

---

### File Storage → Cloudinary (Free 25GB)

Your current setup uses Multer with disk storage (`uploads/` folder).
**This will break on Railway** — Railway's filesystem is ephemeral and resets on every deploy.
Files saved to disk will be lost.

Replace with Cloudinary:

**Install:**
```bash
npm install cloudinary multer-storage-cloudinary
```

**Create `src/uploads/cloudinary.provider.ts`:**
```typescript
import { v2 as cloudinary } from 'cloudinary';
import { ConfigService } from '@nestjs/config';

export const CloudinaryProvider = {
  provide: 'CLOUDINARY',
  inject: [ConfigService],
  useFactory: (config: ConfigService) => {
    return cloudinary.config({
      cloud_name: config.get('CLOUDINARY_CLOUD_NAME'),
      api_key: config.get('CLOUDINARY_API_KEY'),
      api_secret: config.get('CLOUDINARY_API_SECRET'),
    });
  },
};
```

**Add to `.env`:**
```
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret
```

Cloudinary free tier: 25GB storage + 25GB bandwidth/month. More than enough to start.

---

## Option 2 — Low Cost, Production-Ready (~$5–10/month)

| Service | Provider | Cost/month |
|---|---|---|
| NestJS backend | Railway Starter | $5 |
| PostgreSQL | Supabase free | $0 |
| Redis | Upstash | $0–$1 |
| File storage | Cloudinary free | $0 |
| Domain + SSL | Cloudflare | ~$1 (domain ~$10/year) |
| **Total** | | **~$6–7/mo** |

### Why Supabase for PostgreSQL

You're already using `@supabase/supabase-js` in your backend. Using Supabase's
PostgreSQL directly gives you:
- Free 500MB database
- Auto backups
- A visual dashboard to browse your data
- Connection pooling built in

Use the Supabase connection string directly in `DATABASE_URL`.

---

## Option 3 — Completely Free (with trade-offs)

| Service | Provider | Free limit | Trade-off |
|---|---|---|---|
| NestJS | Render.com | 750hrs/month | Sleeps after 15min idle |
| PostgreSQL | Supabase | 500MB | — |
| Redis | Upstash | 10k cmds/day | — |
| File storage | Cloudinary | 25GB | — |
| **Total** | | **$0/mo** | Cold starts on Render |

**Fix Render cold starts** — add a free cron ping:

Your `app.controller.ts` already has a health endpoint. Use
[cron-job.org](https://cron-job.org) (free) to ping it every 10 minutes:
```
GET https://your-app.onrender.com/health
```
This keeps the instance warm and prevents the 30-second cold start delay.

---

## Flutter App — No Hosting Required

Flutter builds native binaries. Distribution options:

| Platform | Cost | Notes |
|---|---|---|
| Google Play Store | $25 one-time | Upload .aab file |
| Apple App Store | $99/year | Requires Mac to build .ipa |
| Direct APK | Free | Share .apk link — Android only, no store |
| Firebase App Distribution | Free | Best for beta testing before launch |
| TestFlight (iOS) | Free | Up to 10,000 beta testers |

---

## What to avoid for Gixbee

| Provider | Why not |
|---|---|
| **Vercel / Netlify** | No WebSocket support — your Socket.io will break completely |
| **Heroku** | Removed free tier, starts at $25/mo |
| **AWS EC2 / GCP VM** | Overkill, complex setup, expensive for small scale |
| **Firebase Hosting** | Static sites only — NestJS won't run |
| **PlanetScale** | MySQL only — you're using PostgreSQL |

---

## Critical fixes before deploying

### 1. CORS — lock it down (currently open to *)

```typescript
// main.ts — update for production
app.enableCors({
  origin: process.env.NODE_ENV === 'production'
    ? ['https://your-railway-domain.railway.app']  // your Flutter web url if applicable
    : '*',
  methods: 'GET,HEAD,PUT,PATCH,POST,DELETE,OPTIONS',
  credentials: true,
});
```

### 2. TypeORM synchronize — must be false in production

```typescript
synchronize: config.get('NODE_ENV') !== 'production',  // already correct in current code
```

### 3. Run migrations on deploy

Railway runs `start:prod` which triggers `migrationsRun: true` in your TypeORM config.
Make sure your migrations folder is compiled into `dist/`:
```bash
# Confirm migrations exist in dist after build:
npm run build && ls dist/migrations/
```

### 4. Update dart-define for production

```bash
flutter build apk \
  --dart-define=API_BASE_URL=https://your-app.railway.app \
  --dart-define=SOCKET_URL=https://your-app.railway.app \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key \
  --dart-define=ONESIGNAL_APP_ID=your-onesignal-id \
  --dart-define=RAZORPAY_KEY=rzp_live_xxx \
  --dart-define=BUILD_VERSION=1.0.0 \
  --release
```

---

## Deployment checklist

- [ ] Backend pushed to GitHub
- [ ] Railway project created, linked to GitHub repo
- [ ] PostgreSQL plugin added in Railway
- [ ] `DATABASE_URL` auto-injected by Railway
- [ ] `REDIS_URL` from Upstash added to Railway env vars
- [ ] All Firebase env vars added (3 vars — not the json file)
- [ ] Cloudinary credentials added
- [ ] `NODE_ENV=production` set
- [ ] CORS updated to restrict origin
- [ ] `synchronize: false` in TypeORM
- [ ] Migrations run on startup (`migrationsRun: true`)
- [ ] Flutter `dart-define` updated to Railway URL
- [ ] WebSocket connection tested from Flutter to Railway
- [ ] `/health` endpoint pinged by cron-job.org (if using Render free tier)
- [ ] `firebase_options.dart` in `.gitignore` — confirmed not committed
- [ ] `firebase-service-account.json` in `.gitignore` — confirmed not committed
