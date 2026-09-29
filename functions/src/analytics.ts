import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

/**
 * Analítica propia y anónima: solo suma contadores por día en stats/{yyyy-mm-dd} (hora de Chile).
 * No usa cookies ni guarda IP, identificadores ni datos personales, así que no requiere banner de consentimiento.
 * La landing y la app llaman a /api/track (rewrite de Hosting) con navigator.sendBeacon.
 *
 * Los números de negocio (inscritos, cuentas, reservas, pagos, retiros) no pasan por aquí: el panel los cuenta
 * directamente en sus colecciones.
 */
const EVENTS = new Set([
  "landing_visit", // una por sesión del navegador en woowfy.com
  "landing_view", // cada página vista en woowfy.com
  "guide_view", // woowfy.com/merchants
  "cta_app", // clic desde la landing hacia la app
  "app_visit", // una por sesión en app.woowfy.com
  "bag_view", // detalle de una bolsa
  "checkout_start", // tocó "Reservar"
]);

const BOT = /bot|crawl|spider|slurp|preview|facebookexternalhit|headless|lighthouse/i;

/** "2026-09-29" en la zona horaria de Chile. */
export function chileDay(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Santiago" }).format(now);
}

export const trackEvent = onRequest({ maxInstances: 5, memory: "256MiB" }, async (req, res) => {
  // Siempre 204: el navegador no espera nada y no le damos pistas a quien intente abusar.
  res.set("Cache-Control", "no-store");
  if (req.method !== "POST" || BOT.test(req.get("user-agent") ?? "")) {
    res.status(204).end();
    return;
  }
  let body: unknown = req.body;
  if (typeof body === "string" || Buffer.isBuffer(body)) {
    try {
      body = JSON.parse(body.toString().slice(0, 200));
    } catch {
      body = null;
    }
  }
  const event = String((body as { e?: unknown } | null)?.e ?? "");
  if (EVENTS.has(event)) {
    await getFirestore().collection("stats").doc(chileDay()).set(
      { day: chileDay(), events: { [event]: FieldValue.increment(1) }, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
  res.status(204).end();
});
