/*
 * Gixbee Admin service worker — minimal, admin-dashboard-appropriate.
 *
 * Strategy:
 *  - /api/*            → NEVER touched. Straight to network. Admin data must
 *                        always be live; caching it would show stale bookings,
 *                        wallets, logs, etc.
 *  - navigations (SPA) → network-first, fall back to cached index.html so the
 *                        app shell opens even on flaky mobile connections.
 *  - hashed assets     → cache-first (Angular fingerprints filenames, so any
 *                        cached copy is immutable by definition).
 *
 * Bump VERSION when you change this file's logic; old caches are dropped on
 * activate. Deploying a new Angular build does NOT require bumping it —
 * new hashed filenames simply enter the cache alongside, and stale entries
 * die with the next version bump.
 */
const VERSION = 'v1';
const CACHE = `gixbee-admin-${VERSION}`;
const APP_SHELL = ['/', '/index.html', '/manifest.webmanifest'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(APP_SHELL)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only handle same-origin GETs. API traffic is explicitly left alone.
  if (req.method !== 'GET') return;
  if (url.origin !== self.location.origin) return;
  if (url.pathname.startsWith('/api/')) return;

  // SPA navigations: network-first with offline fallback to the app shell.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put('/index.html', copy));
          return res;
        })
        .catch(() => caches.match('/index.html')),
    );
    return;
  }

  // Static assets: cache-first, populate on miss.
  event.respondWith(
    caches.match(req).then(
      (hit) =>
        hit ||
        fetch(req).then((res) => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        }),
    ),
  );
});
