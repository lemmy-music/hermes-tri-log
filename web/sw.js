/*
 * Tri-Log – eigener Service Worker (Vanilla JS, keine Abhängigkeiten).
 *
 * Zweck: (a) Die App funktioniert nach dem ersten Aufruf offline,
 *        (b) die Chrome-Installationskriterien für eine echte PWA (WebAPK)
 *            sind erfüllt (registrierter Fetch-Handler).
 *
 * Hintergrund: `flutter build web --release` erzeugt mit Flutter 3.44 nur
 * noch einen Stub-Worker (flutter_service_worker.js), der sich beim
 * Aktivieren selbst abmeldet (flutter/flutter#156910). Deshalb registriert
 * web/index.html diesen Worker – und web/flutter_bootstrap.js registriert
 * Flutters Stub bewusst NICHT (kein `serviceWorkerSettings`).
 *
 * Strategie (bewusst konservativ, damit schnelle Deploys nicht an alten
 * Caches hängen):
 *   - Navigation/HTML, flutter_bootstrap.js, main.dart.js, manifest.json
 *     => NETWORK-FIRST (online immer frisch, offline aus dem Cache)
 *   - alles andere (assets/, icons/, canvaskit/, fonts)
 *     => CACHE-FIRST mit Netz-Fallback und Nachcache
 *
 * CACHE_NAME bei jeder Änderung an diesem Worker erhöhen ("tri-log-v2", …).
 * Kein skipWaiting(): Nutzer sollen nicht mitten in der Session neu laden –
 * die neue Fassung übernimmt beim nächsten kompletten App-Start.
 */

const CACHE_NAME = 'tri-log-v1';

// Alle Pfade RELATIV zum Worker-Skript (Scope z. B. /hermes-tri-log/),
// damit localhost und GitHub Pages gleichermaßen funktionieren.
const CORE_ASSETS = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-180.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
];

// Dateien, die immer zuerst aus dem Netz kommen (frische Deploys).
const NETWORK_FIRST = /(^|\/)(index\.html|flutter_bootstrap\.js|main\.dart\.js|manifest\.json)$/;

// 1) Install: Kern-Dateien vorab cachen. Einzelne Fehler dürfen den
//    Install-Vorgang nicht komplett scheitern lassen (allSettled + Log).
self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      const results = await Promise.allSettled(
        CORE_ASSETS.map((url) =>
          // `cache: 'reload'` umgeht den HTTP-Cache, damit nach einem Deploy
          // nicht die alte index.html vorgehalten wird.
          cache.add(new Request(url, { cache: 'reload' })),
        ),
      );
      results.forEach((result, index) => {
        if (result.status === 'rejected') {
          console.warn('[sw] Vorab-Cache fehlgeschlagen:', CORE_ASSETS[index], result.reason);
        }
      });
      // Bewusst KEIN skipWaiting(): siehe Kommentar oben.
    })(),
  );
});

// 2) Activate: alte Caches aufräumen, sofort alle Clients übernehmen.
self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

// Online immer frisch, bei Netzfehler aus dem Cache.
async function networkFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request);
    if (response && response.ok) {
      await cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const cached = await cache.match(request, { ignoreSearch: true });
    if (cached) return cached;
    // Navigation ohne Treffer: auf die gecachte Startseite zurückfallen.
    if (request.mode === 'navigate') {
      const shell = await cache.match('index.html');
      if (shell) return shell;
    }
    return Response.error();
  }
}

// Aus dem Cache bedienen, sonst aus dem Netz holen und nachcachen.
async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok) {
    await cache.put(request, response.clone());
  }
  return response;
}

// 3) Fetch: nur GET und nur same-origin behandeln; Cross-Origin
//    (z. B. fonts.gstatic.com, www.gstatic.com/canvaskit) wird durchgereicht.
self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  const useNetworkFirst = request.mode === 'navigate' || NETWORK_FIRST.test(url.pathname);
  event.respondWith(useNetworkFirst ? networkFirst(request) : cacheFirst(request));
});
