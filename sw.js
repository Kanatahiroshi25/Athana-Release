'use strict';
/*
 * Athana service worker.
 *
 *  - The page itself is network-first, so a new deploy is always seen (the in-app update checker relies on this),
 *    and the cached copy is used only when the network is down or very slow.
 *  - Icons, the manifest and other files from this site are served from cache and refreshed in the background.
 *  - Library files from the CDNs the page uses (Tailwind, jsmediatags, Font Awesome, kuromoji) are cached the first
 *    time they load, so Athana opens offline afterwards.
 *  - Never touched: /api/ calls, audio range requests, and every other cross-origin request (lyrics, covers,
 *    translation, AI), which always go straight to the network.
 *
 * Bump CACHE_VERSION whenever you change the precached files below.
 */
const CACHE_VERSION = 'v1';
const SHELL = 'athana-shell-' + CACHE_VERSION;
const RUNTIME = 'athana-runtime-' + CACHE_VERSION;
const SCOPE = new URL('./', self.registration.scope).href;
const PRECACHE = ['./', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/icon-maskable-512.png', 'icons/apple-touch-icon-180.png', 'icons/favicon-64.png'];
const CDN_HOSTS = new Set(['cdn.tailwindcss.com', 'cdnjs.cloudflare.com', 'cdn.jsdelivr.net']);
const PAGE_TIMEOUT_MS = 4000;

self.addEventListener('install', e => {
  e.waitUntil(caches.open(SHELL).then(c => Promise.all(PRECACHE.map(u => c.add(u).catch(() => { })))).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith('athana-') && k !== SHELL && k !== RUNTIME) await caches.delete(k);
    await self.clients.claim();
  })());
});

const isPage = (req, url) => req.mode === 'navigate' || url.pathname === new URL(SCOPE).pathname || url.pathname === new URL('index.html', SCOPE).pathname;

async function networkFirst(req, cacheName, timeoutMs) {
  const cache = await caches.open(cacheName);
  const key = new Request(new URL(req.url).origin + new URL(req.url).pathname); // ignore ?query and #hash so every entry point shares one copy
  const fresh = fetch(req).then(res => { if (res && res.ok) cache.put(key, res.clone()); return res; });
  if (!timeoutMs) return fresh.catch(async () => (await cache.match(key)) || Response.error());
  const cached = await cache.match(key);
  if (!cached) return fresh;
  return Promise.race([fresh, new Promise(r => setTimeout(() => r(cached), timeoutMs))]).catch(() => cached);
}

async function staleWhileRevalidate(req, cacheName) {
  const cache = await caches.open(cacheName), hit = await cache.match(req);
  const net = fetch(req).then(res => { if (res && (res.ok || res.type === 'opaque')) cache.put(req, res.clone()); return res; }).catch(() => null);
  return hit || (await net) || Response.error();
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET' || req.headers.has('range')) return; // audio and anything resumable: leave to the browser
  const url = new URL(req.url);
  if (url.origin === self.location.origin) {
    if (url.pathname.startsWith('/api/') || url.pathname.endsWith('/sw.js')) return;
    if (isPage(req, url)) return e.respondWith(networkFirst(req, SHELL, PAGE_TIMEOUT_MS));
    return e.respondWith(staleWhileRevalidate(req, SHELL));
  }
  if (CDN_HOSTS.has(url.hostname)) return e.respondWith(staleWhileRevalidate(req, RUNTIME));
});
