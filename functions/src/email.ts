import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { cancelDeadline } from "./orders.js";

/** API key de Resend (https://resend.com). Se define con: firebase functions:secrets:set RESEND_API_KEY */
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

const APP_URL = "https://app.woowfy.com";

/** Configuración editable desde Admin → Correo (documento config/email). */
interface EmailSettings {
  /** Interruptor general: sin Resend configurado debe quedar apagado. */
  enabled: boolean;
  /** Correos de compra y reembolso (además del interruptor general). */
  orderEmails: boolean;
  fromName: string;
  fromEmail: string;
  replyTo: string | null;
}

const DEFAULTS: EmailSettings = {
  enabled: false, orderEmails: true, fromName: "Woowfy", fromEmail: "hola@woowfy.com", replyTo: "hola@passva.com",
};

/** Único dominio verificado en Resend: la clave solo puede enviar desde aquí. */
const SENDER_DOMAIN = "woowfy.com";

async function emailSettings(): Promise<EmailSettings> {
  const snap = await getFirestore().doc("config/email").get();
  const s = { ...DEFAULTS, ...(snap.data() as Partial<EmailSettings> | undefined) };
  // Un remitente de otro dominio haría fallar todos los envíos: se usa el predeterminado (el admin ya lo valida).
  const fromEmail = s.fromEmail?.toLowerCase().endsWith(`@${SENDER_DOMAIN}`) ? s.fromEmail : DEFAULTS.fromEmail;
  // Las respuestas siempre llegan a un buzón real (woowfy.com solo envía, no recibe).
  return { ...s, fromEmail, replyTo: s.replyTo || DEFAULTS.replyTo };
}

/** woowfy.com ya salió de "en construcción" (config/site, lo cambia el admin con "Lanzar"). */
async function siteLaunched(): Promise<boolean> {
  return (await siteLaunch()).launched;
}

/** Estado del lanzamiento y desde cuándo (launchedAt lo escribe la app al presionar "Lanzar"). */
async function siteLaunch(): Promise<{ launched: boolean; launchedAt?: Date }> {
  const d = (await getFirestore().doc("config/site").get()).data();
  return { launched: d?.launched === true, launchedAt: toDate(d?.launchedAt) };
}

/** Error de Resend con su código HTTP (429 = límite de envíos alcanzado). */
class ResendError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

async function sendEmail(apiKey: string, s: EmailSettings, to: string, subject: string, html: string): Promise<string> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: `${s.fromName} <${s.fromEmail}>`,
      to: [to],
      subject,
      html,
      ...(s.replyTo ? { reply_to: s.replyTo } : {}),
    }),
  });
  const body = (await res.json().catch(() => ({}))) as { id?: string; message?: string };
  if (!res.ok) throw new ResendError(body.message ?? `Resend respondió ${res.status}`, res.status);
  return body.id ?? "";
}

const escape = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const clp = (n: number) => "$" + Math.round(n).toLocaleString("es-CL");

const chileTime = new Intl.DateTimeFormat("es-CL", { timeZone: "America/Santiago", hour: "2-digit", minute: "2-digit", hour12: false });
const chileDate = new Intl.DateTimeFormat("es-CL", { timeZone: "America/Santiago", weekday: "long", day: "numeric", month: "long" });

/** "hoy, martes 29 de septiembre, de 19:00 a 23:00" */
function pickupWindow(start: Date, end: Date): string {
  return `${chileDate.format(start)}, de ${chileTime.format(start)} a ${chileTime.format(end)}`;
}

/** Plantilla común con la paleta de la marca: cabecera verde, tarjeta blanca y pie crema. */
function layout(o: { title: string; body: string; cta?: { label: string; url: string }; footer: string }): string {
  return `<!DOCTYPE html><html lang="es"><body style="margin:0;background:#FFF7E3;font-family:Lato,Arial,sans-serif;color:#101713">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FFF7E3;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:#063B25;padding:28px 32px">
  <img src="https://woowfy.com/icons/icon-192.png" width="56" height="56" alt="" style="vertical-align:middle;border-radius:14px">
  <span style="font-size:30px;font-weight:900;color:#FFF7E3;vertical-align:middle;margin-left:10px;letter-spacing:-1px">woowfy</span>
</td></tr>
<tr><td style="padding:32px">
  <h1 style="margin:0 0 12px;font-size:26px;color:#063B25">${o.title}</h1>
  ${o.body}
  ${o.cta ? `<a href="${o.cta.url}" style="display:inline-block;background:#9BE52C;color:#063B25;font-weight:900;text-decoration:none;padding:14px 26px;border-radius:999px">${o.cta.label}</a>` : ""}
</td></tr>
<tr><td style="padding:20px 32px;background:#FFF7E3;font-size:12px;color:#4E5A53;line-height:1.5">${o.footer}</td></tr>
</table></td></tr></table></body></html>`;
}

const p = (html: string, gap = 16) => `<p style="margin:0 0 ${gap}px;font-size:16px;line-height:1.6">${html}</p>`;

/** Fila "etiqueta: valor" para el resumen del pedido. */
const row = (label: string, value: string) =>
  `<tr><td style="padding:6px 0;color:#4E5A53;font-size:14px;width:40%">${label}</td>` +
  `<td style="padding:6px 0;font-size:15px;font-weight:700;color:#063B25">${value}</td></tr>`;

const summary = (rows: string) =>
  `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;border-top:1px solid #EBDFC3;border-bottom:1px solid #EBDFC3">${rows}</table>`;

const ORDER_FOOTER = "Recibes este correo por una compra en Woowfy. ¿Dudas o problemas con tu pedido? Responde a este correo.";

/** Correo de bienvenida a la lista de espera. Ya lanzada, la lista es para comunas que aún no tienen locales. */
function welcomeEmail(entry: { name?: string; type?: string; businessName?: string | null }, launched = false) {
  const firstName = escape((entry.name ?? "").trim().split(/\s+/)[0] || "");
  const isStore = entry.type === "comercio";
  const body = isStore
    ? `Gracias por querer sumar <strong>${escape(entry.businessName ?? "tu local")}</strong> a Woowfy. ` +
      (launched
        ? "Te contactaremos pronto para conocerlo y dejarlo publicando sus primeras bolsas."
        : "Te contactaremos pronto para conocerlo y dejarlo listo para el lanzamiento.")
    : launched
      ? "Ya estás en la lista de Woowfy. Te avisaremos cuando haya locales en tu comuna; mientras tanto, " +
        "puedes ver las bolsas disponibles en otras comunas desde la app."
      : "Ya estás en la lista de espera de Woowfy. Te avisaremos apenas lancemos para que rescates " +
        "tus primeras bolsas sorpresa a mitad de precio.";
  const subject = isStore ? "Recibimos los datos de tu local 🥐" : `${firstName ? firstName + ", ya" : "Ya"} estás en la lista de Woowfy 🌱`;
  const html = layout({
    title: firstName ? `¡Hola, ${firstName}!` : "¡Hola!",
    body: p(body) + p("Mientras tanto, cuéntale a quien le encante la comida rica y odie botarla. 💚", 24),
    cta: { label: "Visitar woowfy.com", url: "https://woowfy.com" },
    footer: "Recibes este correo porque te inscribiste en woowfy.com. Si no fuiste tú, ignóralo. " +
      "Para que borremos tus datos, responde a este correo.",
  });
  return { subject, html };
}

/** Aviso de lanzamiento a la lista de espera: lo que la landing prometió ("Avísame cuando lancen"). */
function launchEmail(entry: { name?: string; type?: string; businessName?: string | null; comuna?: string }) {
  const firstName = escape((entry.name ?? "").trim().split(/\s+/)[0] || "");
  const isStore = entry.type === "comercio";
  const subject = isStore
    ? "Woowfy ya abrió: suma tu local 🥐"
    : `${firstName ? firstName + ", ¡Woowfy" : "¡Woowfy"} ya abrió! 🌱`;
  const body = isStore
    ? p(`Te inscribiste para sumar <strong>${escape(entry.businessName ?? "tu local")}</strong> a Woowfy, y ya ` +
        "estamos funcionando. Crea tu cuenta, envía la solicitud de tu local y, una vez aprobado, publica tus primeras " +
        "bolsas sorpresa con lo que no alcances a vender en el día.") +
      p("Tú decides cuántas bolsas, a qué precio y en qué horario se retiran. Te transferimos lo vendido cada semana.", 24)
    : p("Te prometimos avisarte y aquí estamos: ya puedes rescatar bolsas sorpresa de panaderías, cafés y " +
        "restaurantes a mitad de precio, y ayudar a que esa comida no se bote.") +
      p("Reserva desde la app, paga en línea y retira en el local con tu código. Si en tu comuna todavía no hay " +
        "locales, vuelve pronto: estamos sumando más.", 24);
  const html = layout({
    title: firstName ? `¡Hola, ${firstName}!` : "¡Hola!",
    body,
    cta: isStore
      ? { label: "Sumar mi local", url: `${APP_URL}/merchant` }
      : { label: "Ver bolsas disponibles", url: APP_URL },
    footer: "Recibes este correo porque te inscribiste en la lista de espera de woowfy.com para que te avisáramos del " +
      "lanzamiento. Es un aviso único: no te enviaremos publicidad sin tu permiso. Para que borremos tus datos, " +
      "responde a este correo.",
  });
  return { subject, html };
}

/** Datos del pedido que usan los correos (los mismos campos que guarda createOrder). */
interface OrderMail {
  id: string;
  storeName: string;
  address: string;
  comuna: string;
  bagTitle: string;
  amount: number;
  pickupStart: Date;
  pickupEnd: Date;
  paidAt?: Date;
  code?: string;
  cancelReason?: string;
  storeMessage?: string;
}

/** Confirmación de compra con el código de retiro. */
function purchaseEmail(o: OrderMail) {
  // Hasta cuándo puede cancelar con reembolso (misma regla que cancelOrder).
  const limit = new Date(cancelDeadline(o.pickupStart.getTime(), o.paidAt?.getTime()));
  const code = o.code
    ? `<div style="margin:0 0 24px;padding:20px;background:#E6F8CC;border-radius:18px;text-align:center">
  <div style="font-size:13px;color:#4E5A53;margin-bottom:6px">Tu código de retiro</div>
  <div style="font-size:34px;font-weight:900;letter-spacing:8px;color:#063B25">${escape(o.code)}</div>
  <div style="font-size:13px;color:#4E5A53;margin-top:6px">Muéstralo en el local (o abre el QR desde la app).</div>
</div>`
    : "";
  const html = layout({
    title: "¡Rescataste una bolsa!",
    body: p(`Tu pago está listo. Ahora solo falta ir a buscarla a <strong>${escape(o.storeName)}</strong>.`) +
      code +
      summary(
        row("Bolsa", escape(o.bagTitle)) +
        row("Local", escape(o.storeName)) +
        row("Dirección", escape(`${o.address}, ${o.comuna}`)) +
        row("Retiro", escape(pickupWindow(o.pickupStart, o.pickupEnd))) +
        row("Pagaste", clp(o.amount)),
      ) +
      p(`<span style="font-size:14px;color:#4E5A53">Si no puedes ir, cancela desde la app hasta el ${escape(chileDate.format(limit))} a las ${chileTime.format(limit)} y te devolvemos el 100%. ` +
        "Llega dentro del horario: antes, tu bolsa puede no estar lista. " +
        "Si no retiras dentro del horario, no hay reembolso: el local la apartó para ti.</span>"),
    cta: { label: "Ver mi pedido y el QR", url: `${APP_URL}/order/${o.id}` },
    footer: ORDER_FOOTER,
  });
  return { subject: `Tu bolsa de ${o.storeName} está lista para retirar`, html };
}

/** Aviso de reembolso, con el motivo. */
function refundEmail(o: OrderMail) {
  const why = o.cancelReason === "store"
    ? `<strong>${escape(o.storeName)}</strong> tuvo que cancelar la bolsa de hoy` +
      (o.storeMessage ? `: "${escape(o.storeMessage)}"` : ".")
    : o.cancelReason === "customer"
      ? "Cancelaste tu pedido a tiempo."
      : "Tu pago llegó cuando la reserva ya había vencido, así que no alcanzamos a apartarte la bolsa.";
  const html = layout({
    title: "Te devolvimos tu dinero",
    body: p(why) +
      summary(
        row("Bolsa", escape(o.bagTitle)) +
        row("Local", escape(o.storeName)) +
        row("Reembolso", clp(o.amount)),
      ) +
      p(`<span style="font-size:14px;color:#4E5A53">El reembolso vuelve al mismo medio de pago. Según tu banco, puede tardar ` +
        "algunos días hábiles en verse en tu cuenta o tarjeta.</span>"),
    cta: { label: "Buscar otra bolsa", url: APP_URL },
    footer: ORDER_FOOTER,
  });
  return { subject: `Reembolso de ${clp(o.amount)} por tu bolsa de ${o.storeName}`, html };
}

const toDate = (v: unknown): Date | undefined => (v instanceof Timestamp ? v.toDate() : undefined);

function orderMail(id: string, d: FirebaseFirestore.DocumentData, code?: string): OrderMail {
  return {
    id,
    storeName: d.storeName ?? "",
    address: d.address ?? "",
    comuna: d.comuna ?? "",
    bagTitle: d.bagTitle ?? "",
    amount: Number(d.refund?.amount ?? d.amount ?? 0),
    pickupStart: toDate(d.pickupStart) ?? new Date(),
    pickupEnd: toDate(d.pickupEnd) ?? new Date(),
    paidAt: toDate(d.paidAt),
    code,
    cancelReason: d.cancelReason,
    storeMessage: d.storeMessage,
  };
}

/** Envía la bienvenida cuando alguien se inscribe en la lista de espera. */
export const onWaitlistCreated = onDocumentCreated(
  { document: "waitlist/{id}", secrets: [RESEND_API_KEY] },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const entry = snap.data();
    // Quien se inscribe ya lanzado no espera el aviso de lanzamiento (la lista queda para comunas sin locales).
    // Se compara con la hora del lanzamiento, no con el estado actual: el trigger puede correr con atraso.
    const site = await siteLaunch();
    const createdAt = toDate(entry.createdAt);
    const launched = site.launched && (!site.launchedAt || !createdAt || createdAt >= site.launchedAt);
    if (launched) {
      // Sin pisar un estado que ya exista (p. ej. si el aviso ya se envió).
      await getFirestore().runTransaction(async (tx) => {
        if ((await tx.get(snap.ref)).data()?.launchEmail) return;
        tx.update(snap.ref, { launchEmail: { status: "skipped", reason: "after_launch", at: FieldValue.serverTimestamp() } });
      });
    }
    const s = await emailSettings();
    if (!s.enabled) {
      await snap.ref.update({ welcomeEmail: { status: "skipped", reason: "disabled", at: FieldValue.serverTimestamp() } });
      return;
    }
    try {
      const { subject, html } = welcomeEmail(entry, launched);
      const id = await sendEmail(RESEND_API_KEY.value(), s, entry.email, subject, html);
      await snap.ref.update({ welcomeEmail: { status: "sent", id, at: FieldValue.serverTimestamp() } });
    } catch (e) {
      logger.error("No se pudo enviar la bienvenida", e);
      await snap.ref.update({
        welcomeEmail: { status: "error", error: String((e as Error).message).slice(0, 300), at: FieldValue.serverTimestamp() },
      });
    }
  },
);

/**
 * Correos del pedido: confirmación al pagarse y aviso cuando se completa un reembolso.
 * Cada correo se "reserva" en orders/{id}.emails.{tipo} dentro de una transacción, así un reintento del trigger no
 * lo manda dos veces. El estado queda registrado (sent | skipped | error) para revisarlo desde la consola.
 */
export const onOrderUpdated = onDocumentUpdated(
  { document: "orders/{id}", secrets: [RESEND_API_KEY] },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const ref = event.data!.after.ref;

    const kind: "purchase" | "refund" | null =
      before.status === "pending_payment" && after.status === "paid" ? "purchase"
        : before.refund?.status !== "done" && after.refund?.status === "done" ? "refund"
          : null;
    if (!kind) return;

    const claimed = await getFirestore().runTransaction(async (tx) => {
      const fresh = (await tx.get(ref)).data();
      if (fresh?.emails?.[kind]) return false;
      tx.update(ref, { [`emails.${kind}`]: { status: "sending", at: FieldValue.serverTimestamp() } });
      return true;
    });
    if (!claimed) return;

    const mark = (status: string, extra: Record<string, unknown> = {}) =>
      ref.update({ [`emails.${kind}`]: { status, ...extra, at: FieldValue.serverTimestamp() } });

    const s = await emailSettings();
    if (!s.enabled || !s.orderEmails) {
      await mark("skipped", { reason: "disabled" });
      return;
    }
    try {
      const to = (await getAuth().getUser(after.userUid)).email;
      if (!to) {
        await mark("skipped", { reason: "no-email" });
        return;
      }
      const code = kind === "purchase"
        ? (await ref.collection("private").doc("pickup").get()).data()?.code as string | undefined
        : undefined;
      const mail = orderMail(ref.id, after, code);
      const { subject, html } = kind === "purchase" ? purchaseEmail(mail) : refundEmail(mail);
      const id = await sendEmail(RESEND_API_KEY.value(), s, to, subject, html);
      await mark("sent", { id });
    } catch (e) {
      logger.error(`No se pudo enviar el correo de ${kind}`, { orderId: ref.id, error: String(e) });
      await mark("error", { error: String((e as Error).message).slice(0, 300) });
    }
  },
);

/** Pedido de ejemplo para las pruebas desde el admin. */
function sampleOrder(): OrderMail {
  const start = new Date(Math.ceil(Date.now() / 3600_000) * 3600_000 + 4 * 3600_000); // en 4-5 h, hora redonda
  return {
    id: "ejemplo", storeName: "Panadería La Espiga", address: "Av. Irarrázaval 1234", comuna: "Ñuñoa",
    bagTitle: "Bolsa sorpresa de panadería", amount: 3490, pickupStart: start,
    pickupEnd: new Date(start.getTime() + 90 * 60_000), paidAt: new Date(), code: "DE7894",
    cancelReason: "store", storeMessage: "Se nos cortó la luz y no pudimos hornear.",
  };
}

/** El correo de ejemplo de cada tipo (welcome | purchase | refund | launch | launch_store), con datos inventados. */
function sampleEmail(kind: string, name = "") {
  switch (kind) {
    case "purchase": return purchaseEmail(sampleOrder());
    case "refund": return refundEmail(sampleOrder());
    case "launch": return launchEmail({ name, type: "cliente" });
    case "launch_store": return launchEmail({ name, type: "comercio", businessName: "Panadería La Espiga" });
    default: return welcomeEmail({ name, type: "cliente" });
  }
}

async function requireAdmin(uid: string | undefined) {
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const user = await getFirestore().doc(`users/${uid}`).get();
  if (user.data()?.role !== "admin") throw new HttpsError("permission-denied", "Solo administradores.");
  return user.data()!;
}

/** Admin → Correo → "Ver plantillas": devuelve el asunto y el HTML de ejemplo para mostrarlos sin enviar nada. */
export const previewEmail = onCall(async (req) => {
  await requireAdmin(req.auth?.uid);
  return sampleEmail(String(req.data?.kind ?? "welcome"), "Camila");
});

/** Admin → Correo → "Enviar prueba": manda un correo de ejemplo al admin con la configuración actual. */
export const sendTestEmail = onCall({ secrets: [RESEND_API_KEY] }, async (req) => {
  const user = await requireAdmin(req.auth?.uid);
  const email = req.auth?.token.email;
  if (!email) throw new HttpsError("failed-precondition", "Tu cuenta no tiene correo.");
  const s = await emailSettings();
  const { subject, html } = sampleEmail(String(req.data?.kind ?? "welcome"), user.name ?? "");
  try {
    const id = await sendEmail(RESEND_API_KEY.value(), s, email, `[Prueba] ${subject}`, html);
    return { id, to: email };
  } catch (e) {
    throw new HttpsError("failed-precondition", (e as Error).message);
  }
});

/** Resend permite unas 2 solicitudes por segundo: se espera entre un envío y otro. */
const LAUNCH_SEND_GAP_MS = 600;
/** Margen para devolver la respuesta antes del tiempo máximo de la función (540 s). */
const LAUNCH_TIME_BUDGET_MS = 480_000;

/**
 * Admin → "Lanzar" → "Enviar aviso": manda el correo de lanzamiento a quienes se inscribieron antes de lanzar.
 * Cada inscrito se "reserva" en una transacción (waitlist/{id}.launchEmail), así un doble clic o un reintento no lo
 * manda dos veces. Si Resend corta por límite (429, p. ej. el tope diario del plan gratis) o se acaba el tiempo, se
 * detiene y devuelve cuántos faltan: se vuelve a presionar más tarde y sigue con los pendientes.
 */
export const sendLaunchEmails = onCall({ secrets: [RESEND_API_KEY], timeoutSeconds: 540 }, async (req) => {
  await requireAdmin(req.auth?.uid);
  if (!(await siteLaunched())) {
    throw new HttpsError("failed-precondition", "Primero lanza woowfy.com: el correo invita a entrar a la app.");
  }
  const s = await emailSettings();
  if (!s.enabled) throw new HttpsError("failed-precondition", "Activa los correos automáticos en Admin → Correo.");

  const db = getFirestore();
  const started = Date.now();
  const all = await db.collection("waitlist").get();
  const pending = all.docs.filter((d) => {
    const status = d.data().launchEmail?.status;
    return status === undefined || status === "error";
  });
  let sent = 0;
  let failed = 0;
  let stoppedBy: "limit" | "time" | null = null;

  for (const doc of pending) {
    if (Date.now() - started > LAUNCH_TIME_BUDGET_MS) {
      stoppedBy = "time";
      break;
    }
    const claimed = await db.runTransaction(async (tx) => {
      const status = (await tx.get(doc.ref)).data()?.launchEmail?.status;
      if (status !== undefined && status !== "error") return false;
      tx.update(doc.ref, { launchEmail: { status: "sending", at: FieldValue.serverTimestamp() } });
      return true;
    });
    if (!claimed) continue;
    const entry = doc.data();
    try {
      const { subject, html } = launchEmail(entry);
      const id = await sendEmail(RESEND_API_KEY.value(), s, entry.email, subject, html);
      await doc.ref.update({ launchEmail: { status: "sent", id, at: FieldValue.serverTimestamp() } });
      sent++;
    } catch (e) {
      const limited = e instanceof ResendError && e.status === 429;
      // Con límite alcanzado no es un error del inscrito: se deja pendiente para el próximo intento.
      await doc.ref.update({
        launchEmail: limited
          ? FieldValue.delete()
          : { status: "error", error: String((e as Error).message).slice(0, 300), at: FieldValue.serverTimestamp() },
      });
      if (limited) {
        stoppedBy = "limit";
        break;
      }
      failed++;
      logger.error("No se pudo enviar el aviso de lanzamiento", { id: doc.id, error: String(e) });
    }
    await new Promise((r) => setTimeout(r, LAUNCH_SEND_GAP_MS));
  }
  const remaining = pending.length - sent - failed;
  logger.info("Aviso de lanzamiento", { sent, failed, remaining, stoppedBy });
  return { sent, failed, remaining, stoppedBy };
});

/** Solo para previsualizar las plantillas en desarrollo (tool/preview-emails.mjs). */
export const _templates = { welcomeEmail, purchaseEmail, refundEmail, launchEmail, sampleOrder };
