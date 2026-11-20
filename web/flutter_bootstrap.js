{{flutter_js}}
{{flutter_build_config}}

// טעינה בלי Service Worker: מונע מצב שבו הדפדפן מגיש גרסה ישנה/חלקית מהמטמון
// והאפליקציה נתקעת על מסך הפתיחה אחרי עדכון.
(async function () {
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations();
      await Promise.all(regs.map(function (r) { return r.unregister(); }));
    }
    if (window.caches && caches.keys) {
      const keys = await caches.keys();
      await Promise.all(keys.filter(function (k) { return k.indexOf('flutter') !== -1; })
        .map(function (k) { return caches.delete(k); }));
    }
  } catch (e) { console.warn('[startup] cache cleanup failed', e); }

  try {
    await _flutter.loader.load({
      onEntrypointLoaded: async function (engineInitializer) {
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      },
    });
  } catch (e) {
    console.error('[startup] Flutter failed to start', e);
    if (window.showAppLoadError) window.showAppLoadError(e);
  }
})();
