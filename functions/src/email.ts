import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

/** API key de Resend (https://resend.com). Se define con: firebase functions:secrets:set RESEND_API_KEY */
const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

/** Configuración editable desde Admin → Correo (documento config/email). */
interface EmailSettings {
  enabled: boolean;
  fromName: string;
  fromEmail: string;
  replyTo: string | null;
}

const DEFAULTS: EmailSettings = { enabled: false, fromName: "Woowfy", fromEmail: "hola@woowfy.com", replyTo: null };

async function emailSettings(): Promise<EmailSettings> {
  const snap = await getFirestore().doc("config/email").get();
  return { ...DEFAULTS, ...(snap.data() as Partial<EmailSettings> | undefined) };
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
  if (!res.ok) throw new Error(body.message ?? `Resend respondió ${res.status}`);
  return body.id ?? "";
}

const escape = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** Correo de bienvenida a la lista de espera, con la paleta de la marca. */
function welcomeEmail(entry: { name?: string; type?: string; businessName?: string | null }) {
  const firstName = escape((entry.name ?? "").trim().split(/\s+/)[0] || "");
  const hello = firstName ? `¡Hola, ${firstName}!` : "¡Hola!";
  const isStore = entry.type === "comercio";
  const body = isStore
    ? `Gracias por querer sumar <strong>${escape(entry.businessName ?? "tu local")}</strong> a Woowfy. ` +
      "Te contactaremos pronto para conocerlo y dejarlo listo para el lanzamiento."
    : "Ya estás en la lista de espera de Woowfy. Te avisaremos apenas lancemos para que rescates " +
      "tus primeras bolsas sorpresa a mitad de precio.";
  const subject = isStore ? "Recibimos los datos de tu local 🥐" : `${firstName ? firstName + ", ya" : "Ya"} estás en la lista de Woowfy 🌱`;
  const html = `<!DOCTYPE html><html lang="es"><body style="margin:0;background:#FFF7E3;font-family:Lato,Arial,sans-serif;color:#101713">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FFF7E3;padding:32px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:24px;overflow:hidden">
<tr><td style="background:#063B25;padding:28px 32px">
  <img src="https://woowfy.com/icons/icon-192.png" width="56" height="56" alt="" style="vertical-align:middle;border-radius:14px">
  <span style="font-size:30px;font-weight:900;color:#FFF7E3;vertical-align:middle;margin-left:10px;letter-spacing:-1px">woowfy</span>
</td></tr>
<tr><td style="padding:32px">
  <h1 style="margin:0 0 12px;font-size:26px;color:#063B25">${hello}</h1>
  <p style="margin:0 0 16px;font-size:16px;line-height:1.6">${body}</p>
  <p style="margin:0 0 24px;font-size:16px;line-height:1.6">Mientras tanto, cuéntale a quien le encante la comida rica y odie botarla. 💚</p>
  <a href="https://woowfy.com" style="display:inline-block;background:#9BE52C;color:#063B25;font-weight:900;text-decoration:none;padding:14px 26px;border-radius:999px">Visitar woowfy.com</a>
</td></tr>
<tr><td style="padding:20px 32px;background:#FFF7E3;font-size:12px;color:#4E5A53;line-height:1.5">
  Recibes este correo porque te inscribiste en woowfy.com. Si no fuiste tú, ignóralo.
  Para que borremos tus datos, responde a este correo.
</td></tr></table></td></tr></table></body></html>`;
  return { subject, html };
}

/** Envía la bienvenida cuando alguien se inscribe en la lista de espera. */
export const onWaitlistCreated = onDocumentCreated(
  { document: "waitlist/{id}", secrets: [RESEND_API_KEY] },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const entry = snap.data();
    const s = await emailSettings();
    if (!s.enabled) {
      await snap.ref.update({ welcomeEmail: { status: "skipped", reason: "disabled", at: FieldValue.serverTimestamp() } });
      return;
    }
    try {
      const { subject, html } = welcomeEmail(entry);
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

/** Admin → Correo → "Enviar prueba": manda la bienvenida al correo del admin con la configuración actual. */
export const sendTestEmail = onCall({ secrets: [RESEND_API_KEY] }, async (req) => {
  const uid = req.auth?.uid;
  const email = req.auth?.token.email;
  if (!uid || !email) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const user = await getFirestore().doc(`users/${uid}`).get();
  if (user.data()?.role !== "admin") throw new HttpsError("permission-denied", "Solo administradores.");

  const s = await emailSettings();
  const { subject, html } = welcomeEmail({ name: user.data()?.name ?? "", type: "cliente" });
  try {
    const id = await sendEmail(RESEND_API_KEY.value(), s, email, `[Prueba] ${subject}`, html);
    return { id, to: email };
  } catch (e) {
    throw new HttpsError("failed-precondition", (e as Error).message);
  }
});
