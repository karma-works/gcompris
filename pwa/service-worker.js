const CACHE_NAME = "gcompris-26.1-df44dc0f5381";
const PRECACHE_URLS = [
  "gcompris-qt.html",
  "gcompris-qt.js",
  "icon-192.png",
  "icon-512.png",
  "index.html",
  "logo.png",
  "manifest.webmanifest",
  "qtloader.js",
  "share/gcompris-qt/rcc/activities.rcc",
  "share/gcompris-qt/rcc/activities_light.rcc",
  "share/gcompris-qt/rcc/core.rcc",
  "share/gcompris-qt/rcc/menu.rcc",
  "share/gcompris-qt/translations/gcompris_qt_ar.qm",
  "share/gcompris-qt/translations/gcompris_qt_az.qm",
  "share/gcompris-qt/translations/gcompris_qt_be.qm",
  "share/gcompris-qt/translations/gcompris_qt_bg.qm",
  "share/gcompris-qt/translations/gcompris_qt_br.qm",
  "share/gcompris-qt/translations/gcompris_qt_ca.qm",
  "share/gcompris-qt/translations/gcompris_qt_ca@valencia.qm",
  "share/gcompris-qt/translations/gcompris_qt_cs.qm",
  "share/gcompris-qt/translations/gcompris_qt_de.qm",
  "share/gcompris-qt/translations/gcompris_qt_el.qm",
  "share/gcompris-qt/translations/gcompris_qt_en.qm",
  "share/gcompris-qt/translations/gcompris_qt_en_GB.qm",
  "share/gcompris-qt/translations/gcompris_qt_eo.qm",
  "share/gcompris-qt/translations/gcompris_qt_es.qm",
  "share/gcompris-qt/translations/gcompris_qt_et.qm",
  "share/gcompris-qt/translations/gcompris_qt_eu.qm",
  "share/gcompris-qt/translations/gcompris_qt_fi.qm",
  "share/gcompris-qt/translations/gcompris_qt_fr.qm",
  "share/gcompris-qt/translations/gcompris_qt_gl.qm",
  "share/gcompris-qt/translations/gcompris_qt_he.qm",
  "share/gcompris-qt/translations/gcompris_qt_hr.qm",
  "share/gcompris-qt/translations/gcompris_qt_hu.qm",
  "share/gcompris-qt/translations/gcompris_qt_id.qm",
  "share/gcompris-qt/translations/gcompris_qt_it.qm",
  "share/gcompris-qt/translations/gcompris_qt_ka.qm",
  "share/gcompris-qt/translations/gcompris_qt_kn.qm",
  "share/gcompris-qt/translations/gcompris_qt_lt.qm",
  "share/gcompris-qt/translations/gcompris_qt_lv.qm",
  "share/gcompris-qt/translations/gcompris_qt_mk.qm",
  "share/gcompris-qt/translations/gcompris_qt_ml.qm",
  "share/gcompris-qt/translations/gcompris_qt_nl.qm",
  "share/gcompris-qt/translations/gcompris_qt_nn.qm",
  "share/gcompris-qt/translations/gcompris_qt_pl.qm",
  "share/gcompris-qt/translations/gcompris_qt_pt.qm",
  "share/gcompris-qt/translations/gcompris_qt_pt_BR.qm",
  "share/gcompris-qt/translations/gcompris_qt_ro.qm",
  "share/gcompris-qt/translations/gcompris_qt_ru.qm",
  "share/gcompris-qt/translations/gcompris_qt_sa.qm",
  "share/gcompris-qt/translations/gcompris_qt_sk.qm",
  "share/gcompris-qt/translations/gcompris_qt_sl.qm",
  "share/gcompris-qt/translations/gcompris_qt_sq.qm",
  "share/gcompris-qt/translations/gcompris_qt_sv.qm",
  "share/gcompris-qt/translations/gcompris_qt_sw.qm",
  "share/gcompris-qt/translations/gcompris_qt_ta.qm",
  "share/gcompris-qt/translations/gcompris_qt_tr.qm",
  "share/gcompris-qt/translations/gcompris_qt_uk.qm",
  "share/gcompris-qt/translations/gcompris_qt_zh_TW.qm"
];

self.addEventListener("install", event => {
  // Precache each URL independently. cache.addAll() rejects atomically if any
  // single request fails (e.g. a momentarily-missing asset), which would leave
  // the previous, possibly broken, service worker active. allSettled lets the
  // new worker install and take over even if some assets are not yet available;
  // the runtime fetch handler will cache them on demand later.
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => Promise.allSettled(
        PRECACHE_URLS.map(url => cache.add(url).catch(err => {
          console.warn("Service worker precache skipped", url, err);
        }))
      ))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys
        .filter(key => key.startsWith("gcompris-") && key !== CACHE_NAME)
        .map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  if (event.request.method !== "GET") {
    return;
  }
  // Let large binary assets (.data, .wasm) pass through to the browser HTTP cache.
  const url = new URL(event.request.url);
  if (url.pathname.endsWith(".data") || url.pathname.endsWith(".wasm")) {
    return;
  }
  const isLazyDataResource = url.pathname.includes("/data3/voices-") ||
    url.pathname.includes("/data3/backgroundMusic/") ||
    url.pathname.includes("/data3/words/");
  const isActivityResource = url.pathname.includes("/share/gcompris-qt/rcc/") &&
    url.pathname.endsWith(".rcc") &&
    !url.pathname.includes("/data3/");
  if (isLazyDataResource || isActivityResource) {
    event.respondWith(
      caches.open(CACHE_NAME).then(cache =>
        cache.match(event.request).then(cached => {
          if (cached) {
            return cached;
          }
          return fetch(event.request).then(response => {
            if (response.ok) {
              cache.put(event.request, response.clone());
            }
            return response;
          });
        })
      )
    );
    return;
  }
  event.respondWith(
    caches.match(event.request).then(cached => {
      if (cached) {
        return cached;
      }
      if (event.request.mode === "navigate") {
        return caches.match("index.html");
      }
      return fetch(event.request);
    })
  );
});
