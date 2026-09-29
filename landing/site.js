// Modo de la landing: "en construcción" o "lanzada". Lo cambia el admin en la app (Admin → Interesados), que
// guarda config/site { launched } en Firestore; esta página lo lee con la API REST (lectura pública solo de ese
// documento). Los elementos con data-prelaunch se ven antes del lanzamiento y los data-launch después.
(function () {
  const KEY = 'woowfy.launched';
  const root = document.documentElement;
  const apply = (launched) => root.classList.toggle('launched', launched);

  // Último valor conocido primero, para que no parpadee al recargar.
  try { apply(localStorage.getItem(KEY) === '1'); } catch (e) { /* sin almacenamiento: queda en construcción */ }

  fetch('https://firestore.googleapis.com/v1/projects/woowfy-app/databases/(default)/documents/config/site')
    .then((r) => (r.ok ? r.json() : null))
    .then((doc) => {
      const launched = doc?.fields?.launched?.booleanValue === true;
      apply(launched);
      try { localStorage.setItem(KEY, launched ? '1' : '0'); } catch (e) { /* ignorar */ }
    })
    .catch(() => { /* sin conexión o sin documento: se mantiene el último modo */ });
})();

// Analítica anónima: solo suma contadores por día (sin cookies ni datos personales). Ver functions/src/analytics.ts.
(function () {
  if (['localhost', '127.0.0.1'].includes(location.hostname)) return;
  const track = (e) => {
    try { navigator.sendBeacon('/api/track', JSON.stringify({ e })); } catch (err) { /* ignorar */ }
  };
  try {
    if (!sessionStorage.getItem('woowfy.visit')) {
      sessionStorage.setItem('woowfy.visit', '1');
      track('landing_visit');
    }
  } catch (err) { /* sin almacenamiento: no contamos la visita */ }
  track(location.pathname.startsWith('/merchants') ? 'guide_view' : 'landing_view');
  // Clics que llevan a la app (solo tienen efecto con la landing lanzada).
  document.addEventListener('click', (ev) => {
    const a = ev.target.closest && ev.target.closest('a[href^="https://app.woowfy.com"]');
    if (a) track('cta_app');
  });
})();
