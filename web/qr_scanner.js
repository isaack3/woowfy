// Escáner de QR para la versión web (app.woowfy.com). Es una capa HTML sobre la app, sin pasar por Flutter:
// así funciona igual en Safari de iPhone, Chrome de Android y computadores.
//
//   const code = await window.woowfyQr.scan();   // "AB12CD", o null si se cerró / eligió escribir el código
//
// Receta estándar para iPhone: getUserMedia + <video playsinline muted autoplay> + lectura de cuadros en un canvas.
// Decodifica con BarcodeDetector cuando el navegador lo trae (Chrome/Android) y si no con jsQR.
(function () {
  const JSQR_URL = 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js';
  const CODE = /^[A-Z0-9]{6}$/;
  let jsqrLoading = null;

  function loadJsQr() {
    if (window.jsQR) return Promise.resolve();
    if (!jsqrLoading) {
      jsqrLoading = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = JSQR_URL;
        s.async = true;
        s.onload = () => resolve();
        s.onerror = () => { jsqrLoading = null; s.remove(); reject(new Error('script')); };
        document.head.appendChild(s);
      });
    }
    return jsqrLoading;
  }

  function friendlyError(err) {
    const name = (err && err.name) || '';
    const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
    if (name === 'NotAllowedError' || name === 'SecurityError') {
      return ios
        ? 'No hay permiso para usar la cámara. En Safari toca "aA" en la barra de direcciones → Ajustes del sitio web → Cámara → Permitir, y luego Reintentar.'
        : 'No hay permiso para usar la cámara. Actívalo en el ícono de la barra de direcciones y luego toca Reintentar.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') return 'No encontramos una cámara en este equipo.';
    if (name === 'NotReadableError' || name === 'AbortError') return 'La cámara está ocupada por otra app. Ciérrala y toca Reintentar.';
    if (err && err.message === 'script') return 'No pudimos cargar el lector de QR. Revisa tu conexión y toca Reintentar.';
    if (err && err.message === 'unsupported') {
      return 'Este navegador no permite usar la cámara. Abre app.woowfy.com directamente en Safari o Chrome.';
    }
    if (err && err.message === 'timeout') return 'La cámara no está enviando imagen. Toca Reintentar.';
    return 'No pudimos abrir la cámara' + (name ? ' (' + name + ')' : '') + '. Toca Reintentar o escribe el código.';
  }

  const CSS = `
  .wq{position:fixed;inset:0;z-index:2147483647;background:#000;display:flex;flex-direction:column;font-family:Lato,system-ui,sans-serif;color:#fff;-webkit-user-select:none;user-select:none}
  .wq-top{display:flex;align-items:center;gap:12px;background:#063B25;color:#FFF7E3;padding:calc(env(safe-area-inset-top) + 12px) 16px 12px;font-weight:900;font-size:20px}
  .wq-top button{background:none;border:0;color:#FFF7E3;font-size:28px;line-height:1;padding:4px 8px;cursor:pointer}
  .wq-stage{position:relative;flex:1;overflow:hidden}
  .wq-stage video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
  .wq-frame{position:absolute;left:50%;top:50%;width:240px;height:240px;transform:translate(-50%,-50%);border:4px solid #9BE52C;border-radius:24px;box-shadow:0 0 0 9999px rgba(0,0,0,.35)}
  .wq-hint{position:absolute;left:16px;right:16px;bottom:calc(env(safe-area-inset-bottom) + 28px);text-align:center;display:flex;flex-direction:column;align-items:center;gap:14px}
  .wq-hint b{font-size:17px}
  .wq-btn{border:0;border-radius:999px;padding:14px 26px;font:inherit;font-weight:900;font-size:16px;cursor:pointer}
  .wq-lime{background:#9BE52C;color:#063B25}
  .wq-ghost{background:rgba(255,255,255,.12);color:#fff}
  .wq-msg{position:absolute;inset:0;background:rgba(0,0,0,.88);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:32px;text-align:center;font-size:16px;line-height:1.5}
  .wq-msg[hidden]{display:none}
  .wq-spin{width:36px;height:36px;border:4px solid rgba(155,229,44,.3);border-top-color:#9BE52C;border-radius:50%;animation:wqspin 1s linear infinite}
  @keyframes wqspin{to{transform:rotate(360deg)}}`;

  function scan() {
    return new Promise((resolve) => {
      if (!document.getElementById('wq-style')) {
        const st = document.createElement('style');
        st.id = 'wq-style';
        st.textContent = CSS;
        document.head.appendChild(st);
      }
      const root = document.createElement('div');
      root.className = 'wq';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-label', 'Escanear QR');
      root.innerHTML = `
        <div class="wq-top"><button type="button" data-a="close" aria-label="Cerrar">×</button>Escanear QR</div>
        <div class="wq-stage">
          <video playsinline muted autoplay></video>
          <div class="wq-frame" aria-hidden="true"></div>
          <div class="wq-hint"><b>Apunta al QR del cliente</b>
            <button type="button" class="wq-btn wq-ghost" data-a="manual">Escribir el código</button></div>
          <div class="wq-msg" data-m="loading"><div class="wq-spin"></div><div>Abriendo la cámara…</div></div>
          <div class="wq-msg" data-m="error" hidden><div data-t></div>
            <button type="button" class="wq-btn wq-lime" data-a="retry">Reintentar</button>
            <button type="button" class="wq-btn wq-ghost" data-a="manual">Escribir el código</button></div>
        </div>`;
      document.body.appendChild(root);

      const video = root.querySelector('video');
      // Por si algún navegador ignora los atributos del HTML: en iPhone sin playsinline el video no se muestra.
      video.setAttribute('playsinline', '');
      video.playsInline = true;
      video.muted = true;
      const loading = root.querySelector('[data-m=loading]');
      const errorBox = root.querySelector('[data-m=error]');
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      let stream = null, timer = null, watchdog = null, detector = null, busy = false, done = false;

      function stopCamera() {
        clearInterval(timer); clearTimeout(watchdog); timer = null;
        if (stream) stream.getTracks().forEach((t) => t.stop());
        stream = null;
        video.srcObject = null;
      }
      function finish(value) {
        if (done) return;
        done = true;
        stopCamera();
        document.removeEventListener('keydown', onKey);
        root.remove();
        resolve(value);
      }
      function showError(err) {
        stopCamera();
        loading.hidden = true;
        errorBox.querySelector('[data-t]').textContent = friendlyError(err);
        errorBox.hidden = false;
        if (window.console) console.warn('[woowfyQr]', err && (err.name || err.message), err);
      }
      function onKey(e) { if (e.key === 'Escape') finish(null); }
      document.addEventListener('keydown', onKey);
      root.addEventListener('click', (e) => {
        const a = e.target.closest('[data-a]');
        if (!a) return;
        if (a.dataset.a === 'close' || a.dataset.a === 'manual') finish(null);
        if (a.dataset.a === 'retry') start();
      });

      function accept(raw) {
        const code = String(raw || '').trim().toUpperCase();
        if (!CODE.test(code)) return false;
        if (navigator.vibrate) navigator.vibrate(60);
        finish(code);
        return true;
      }

      async function tick() {
        if (busy || done || video.readyState < 2 || !video.videoWidth) return;
        busy = true;
        try {
          if (detector) {
            const found = await detector.detect(video);
            for (const b of found) if (accept(b.rawValue)) return;
          } else if (window.jsQR) {
            // Cuadro reducido (máx. 640 px de ancho): suficiente para un QR y liviano en celulares.
            const scale = Math.min(1, 640 / video.videoWidth);
            canvas.width = Math.round(video.videoWidth * scale);
            canvas.height = Math.round(video.videoHeight * scale);
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
            const r = window.jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
            if (r) accept(r.data);
          }
        } catch (err) {
          // Un cuadro que falla no detiene el escáner.
        } finally {
          busy = false;
        }
      }

      async function start() {
        stopCamera();
        errorBox.hidden = true;
        loading.hidden = false;
        try {
          if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.isSecureContext) {
            throw new Error('unsupported');
          }
          if ('BarcodeDetector' in window) {
            try {
              const formats = await window.BarcodeDetector.getSupportedFormats();
              if (formats.includes('qr_code')) detector = new window.BarcodeDetector({ formats: ['qr_code'] });
            } catch (e) { detector = null; }
          }
          // Se piden en paralelo: el permiso de cámara aparece de inmediato mientras se descarga el lector.
          const reader = detector ? Promise.resolve() : loadJsQr();
          stream = await navigator.mediaDevices.getUserMedia({
            audio: false,
            video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
          });
          if (done) { stopCamera(); return; }
          video.srcObject = stream;
          watchdog = setTimeout(() => { if (!video.videoWidth) showError(new Error('timeout')); }, 8000);
          await video.play();
          await reader;
          loading.hidden = true;
          timer = setInterval(tick, 150);
        } catch (err) {
          showError(err);
        }
      }

      start();
    });
  }

  // ---------------------------------------------------------------------------------------------------------------
  // Modo mostrador: la cámara queda abierta y se validan clientes uno tras otro.
  //
  //   await window.woowfyQr.counter({ pending: 4, validate: async (code) => ({ ok, title, detail }) });
  //
  // validate() la entrega la app (llama al servidor). Si ok: pantalla verde, vibra y vuelve a escanear sola en 3 s.
  // Si no: pantalla coral con vibración doble, y espera a que el comercio toque "Entendido".
  const COUNTER_CSS = `
  .wq-count{margin-left:auto;font-size:15px;font-weight:700;color:#9BE52C}
  .wq-res{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;padding:32px;text-align:center}
  .wq-res[hidden]{display:none}
  .wq-ok{background:#063B25;color:#FFF7E3}
  .wq-bad{background:#B83A22;color:#fff}
  .wq-warn{background:#F5B53D;color:#3A2600}
  .wq-warn .wq-btn.wq-line{background:transparent;border:2px solid #3A2600;color:#3A2600}
  .wq-res .wq-icon{font-size:64px;line-height:1}
  .wq-res h2{margin:0;font-size:28px;font-weight:900;line-height:1.15}
  .wq-res p{margin:0;font-size:18px;line-height:1.4}
  .wq-ok .wq-detail{color:#9BE52C;font-weight:700}
  .wq-res .wq-kicker{font-size:15px;font-weight:700;letter-spacing:.04em;opacity:.85}
  .wq-res .wq-btn{margin-top:20px;min-width:240px}
  .wq-white{background:#fff;color:#B83A22}
  .wq-manual{display:flex;gap:8px;justify-content:center}
  .wq-manual input{width:150px;border:0;border-radius:999px;padding:14px 18px;font:inherit;font-size:18px;font-weight:900;letter-spacing:4px;text-transform:uppercase;text-align:center}`;

  let audio = null;
  function unlockAudio() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return;
      if (!audio) audio = new Ctx();
      if (audio.state === 'suspended') audio.resume();
    } catch (e) { audio = null; }
  }
  // ok: un tono agudo y corto. No ok: dos tonos graves.
  function beep(ok) {
    if (!audio) return;
    try {
      const notes = ok ? [[880, 0, 0.14]] : [[220, 0, 0.18], [220, 0.26, 0.18]];
      for (const [freq, at, len] of notes) {
        const osc = audio.createOscillator();
        const gain = audio.createGain();
        osc.type = ok ? 'sine' : 'square';
        osc.frequency.value = freq;
        const t0 = audio.currentTime + at;
        gain.gain.setValueAtTime(0.0001, t0);
        gain.gain.exponentialRampToValueAtTime(0.25, t0 + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + len);
        osc.connect(gain).connect(audio.destination);
        osc.start(t0);
        osc.stop(t0 + len + 0.02);
      }
    } catch (e) { /* sin sonido no pasa nada */ }
  }

  function counter(opts) {
    unlockAudio();
    const validate = opts && opts.validate;
    let pending = (opts && typeof opts.pending === 'number') ? opts.pending : null;
    return new Promise((resolve) => {
      if (!document.getElementById('wq-style')) {
        const st = document.createElement('style');
        st.id = 'wq-style';
        st.textContent = CSS;
        document.head.appendChild(st);
      }
      if (!document.getElementById('wq-counter-style')) {
        const st = document.createElement('style');
        st.id = 'wq-counter-style';
        st.textContent = COUNTER_CSS;
        document.head.appendChild(st);
      }
      const root = document.createElement('div');
      root.className = 'wq';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-modal', 'true');
      root.setAttribute('aria-label', 'Modo mostrador');
      root.innerHTML = `
        <div class="wq-top"><button type="button" data-a="close" aria-label="Salir del mostrador">×</button>Mostrador
          <span class="wq-count" data-count aria-live="polite"></span></div>
        <div class="wq-stage">
          <video playsinline muted autoplay></video>
          <div class="wq-frame" aria-hidden="true"></div>
          <div class="wq-hint"><b>Apunta al QR del cliente</b>
            <form class="wq-manual" data-manual hidden>
              <input maxlength="6" autocomplete="off" autocapitalize="characters" aria-label="Código de retiro" placeholder="CÓDIGO">
              <button type="submit" class="wq-btn wq-lime">Validar</button></form>
            <button type="button" class="wq-btn wq-ghost" data-a="type">Escribir el código</button></div>
          <div class="wq-msg" data-m="loading"><div class="wq-spin"></div><div data-lt>Abriendo la cámara…</div></div>
          <div class="wq-msg" data-m="error" hidden><div data-t></div>
            <button type="button" class="wq-btn wq-lime" data-a="retry">Reintentar</button>
            <button type="button" class="wq-btn wq-ghost" data-a="type">Escribir el código</button></div>
          <div class="wq-res wq-ok" data-m="ok" hidden role="status" aria-live="assertive">
            <div class="wq-icon" aria-hidden="true">✓</div><p class="wq-kicker">Entrega</p><h2 data-title></h2><p class="wq-detail" data-detail></p>
            <p data-left></p>
            <button type="button" class="wq-btn wq-lime" data-a="next">Siguiente cliente</button></div>
          <div class="wq-res wq-bad" data-m="bad" hidden role="alert">
            <div class="wq-icon" aria-hidden="true">✋</div><h2 data-title></h2><p data-detail></p>
            <button type="button" class="wq-btn wq-white" data-a="next">Entendido, escanear otro</button></div>
          <div class="wq-res wq-warn" data-m="warn" hidden role="alert">
            <div class="wq-icon" aria-hidden="true">⏰</div><h2 data-title></h2><p data-detail></p>
            <p>Entrégala solo si ya está lista.</p>
            <button type="button" class="wq-btn wq-lime" data-a="force">Entregar igual</button>
            <button type="button" class="wq-btn wq-line" data-a="next">No entregar, siguiente</button></div>
        </div>`;
      document.body.appendChild(root);

      const video = root.querySelector('video');
      video.setAttribute('playsinline', '');
      video.playsInline = true;
      video.muted = true;
      const loading = root.querySelector('[data-m=loading]');
      const errorBox = root.querySelector('[data-m=error]');
      const okBox = root.querySelector('[data-m=ok]');
      const badBox = root.querySelector('[data-m=bad]');
      const warnBox = root.querySelector('[data-m=warn]');
      let earlyCode = null;
      const manual = root.querySelector('[data-manual]');
      const countEl = root.querySelector('[data-count]');
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      let stream = null, timer = null, watchdog = null, detector = null, busy = false, done = false;
      let paused = false, nextTimer = null, lastCode = null, lastAt = 0;

      function renderCount() {
        countEl.textContent = pending === null ? '' : 'Por retirar: ' + pending;
      }
      renderCount();

      function stopCamera() {
        clearInterval(timer); clearTimeout(watchdog); timer = null;
        if (stream) stream.getTracks().forEach((t) => t.stop());
        stream = null;
        video.srcObject = null;
      }
      function finish() {
        if (done) return;
        done = true;
        clearTimeout(nextTimer);
        stopCamera();
        document.removeEventListener('keydown', onKey);
        root.remove();
        resolve(null);
      }
      function showError(err) {
        stopCamera();
        loading.hidden = true;
        errorBox.querySelector('[data-t]').textContent = friendlyError(err);
        errorBox.hidden = false;
      }
      function resume() {
        clearTimeout(nextTimer);
        okBox.hidden = true;
        badBox.hidden = true;
        warnBox.hidden = true;
        earlyCode = null;
        paused = false;
      }
      function onKey(e) {
        if (e.key === 'Escape') finish();
        if (e.key === 'Enter' && (!okBox.hidden || !badBox.hidden || !warnBox.hidden)) resume();
      }
      document.addEventListener('keydown', onKey);
      root.addEventListener('click', (e) => {
        unlockAudio(); // en iPhone el audio solo se habilita con un toque
        const a = e.target.closest('[data-a]');
        if (!a) return;
        if (a.dataset.a === 'close') finish();
        if (a.dataset.a === 'retry') start();
        if (a.dataset.a === 'next') resume();
        if (a.dataset.a === 'force' && earlyCode) { const c = earlyCode; warnBox.hidden = true; earlyCode = null; check(c, true); }
        if (a.dataset.a === 'type') {
          errorBox.hidden = true;
          manual.hidden = false;
          a.hidden = true;
          manual.querySelector('input').focus();
        }
      });
      manual.addEventListener('submit', (e) => {
        e.preventDefault();
        const input = manual.querySelector('input');
        const code = input.value.trim().toUpperCase();
        if (!CODE.test(code)) { input.focus(); return; }
        input.value = '';
        input.blur();
        check(code);
      });

      async function check(code, force) {
        paused = true;
        loading.querySelector('[data-lt]').textContent = 'Validando ' + code + '…';
        loading.hidden = false;
        let r;
        try {
          r = await validate(code, !!force);
        } catch (err) {
          r = { ok: false, title: 'No se pudo validar', detail: 'Revisa tu conexión e intenta de nuevo.', retry: true };
        }
        loading.hidden = true;
        loading.querySelector('[data-lt]').textContent = 'Abriendo la cámara…';
        if (done) return;
        const box = r && r.ok ? okBox : r && r.early ? warnBox : badBox;
        if (r && r.early) earlyCode = code;
        box.querySelector('[data-title]').textContent = (r && r.title) || '';
        box.querySelector('[data-detail]').textContent = (r && r.detail) || '';
        // Error de conexión: el mismo QR se puede volver a leer apenas se toque "Entendido".
        if (r && r.retry) lastCode = null;
        beep(!!(r && r.ok));
        if (r && r.ok) {
          if (pending !== null && pending > 0) pending -= 1;
          renderCount();
          okBox.querySelector('[data-left]').textContent =
            pending === null ? '' : pending === 0 ? 'No quedan retiros pendientes' : 'Quedan ' + pending + ' por retirar';
          if (navigator.vibrate) navigator.vibrate(80);
          nextTimer = setTimeout(resume, 3000);
        } else if (navigator.vibrate) {
          navigator.vibrate([150, 90, 150]);
        }
        box.hidden = false;
        box.querySelector(r && r.early ? '[data-a=force]' : '[data-a=next]').focus();
      }

      function accept(raw) {
        const code = String(raw || '').trim().toUpperCase();
        if (!CODE.test(code)) return false;
        // El mismo QR sigue frente a la cámara un rato: no se valida dos veces seguidas.
        if (code === lastCode && Date.now() - lastAt < 8000) return false;
        lastCode = code;
        lastAt = Date.now();
        check(code);
        return true;
      }

      async function tick() {
        if (paused || busy || done || video.readyState < 2 || !video.videoWidth) return;
        busy = true;
        try {
          if (detector) {
            const found = await detector.detect(video);
            for (const b of found) if (accept(b.rawValue)) return;
          } else if (window.jsQR) {
            const scale = Math.min(1, 640 / video.videoWidth);
            canvas.width = Math.round(video.videoWidth * scale);
            canvas.height = Math.round(video.videoHeight * scale);
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
            const r = window.jsQR(img.data, img.width, img.height, { inversionAttempts: 'dontInvert' });
            if (r) accept(r.data);
          }
        } catch (err) {
          // Un cuadro que falla no detiene el escáner.
        } finally {
          busy = false;
        }
      }

      async function start() {
        stopCamera();
        errorBox.hidden = true;
        loading.hidden = false;
        try {
          if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || !window.isSecureContext) {
            throw new Error('unsupported');
          }
          if ('BarcodeDetector' in window) {
            try {
              const formats = await window.BarcodeDetector.getSupportedFormats();
              if (formats.includes('qr_code')) detector = new window.BarcodeDetector({ formats: ['qr_code'] });
            } catch (e) { detector = null; }
          }
          const reader = detector ? Promise.resolve() : loadJsQr();
          stream = await navigator.mediaDevices.getUserMedia({
            audio: false,
            video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
          });
          if (done) { stopCamera(); return; }
          video.srcObject = stream;
          watchdog = setTimeout(() => { if (!video.videoWidth) showError(new Error('timeout')); }, 8000);
          await video.play();
          await reader;
          loading.hidden = true;
          timer = setInterval(tick, 150);
        } catch (err) {
          showError(err);
        }
      }

      start();
    });
  }

  window.woowfyQr = { scan, counter };
})();
