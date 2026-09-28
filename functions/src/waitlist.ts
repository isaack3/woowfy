import { createHash } from "node:crypto";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { CHILE_REGIONS } from "./chile.js";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/**
 * Lista de espera de la landing ("Avísame cuando lancen").
 * En producción se llama como /api/waitlist (rewrite de Hosting, mismo origen).
 * Guarda en `waitlist/{hash del correo}` para no duplicar; solo el admin puede leerla.
 */
export const joinWaitlist = onRequest({
  maxInstances: 5,
  cors: [
    /^https:\/\/(www\.)?woowfy\.com$/,
    /^https:\/\/woowfy-app\.(web\.app|firebaseapp\.com)$/,
    /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/,
  ],
}, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Método no permitido." });
    return;
  }
  const body = req.body ?? {};
  // Campo trampa: invisible para personas, los bots suelen llenarlo.
  if (body.website) {
    res.json({ ok: true });
    return;
  }

  const name = String(body.name ?? "").trim().replace(/\s+/g, " ").slice(0, 60);
  const email = String(body.email ?? "").trim().toLowerCase();
  const type = body.type === "comercio" ? "comercio" : "cliente";
  const region = String(body.region ?? "");
  const comuna = String(body.comuna ?? "").trim().slice(0, 60);
  const businessName = type === "comercio" ? String(body.businessName ?? "").trim().slice(0, 100) : null;

  if (!name) {
    res.status(400).json({ error: "Cuéntanos tu nombre." });
    return;
  }
  if (email.length > 254 || !EMAIL_RE.test(email)) {
    res.status(400).json({ error: "Revisa tu correo." });
    return;
  }
  if (!(CHILE_REGIONS as readonly string[]).includes(region)) {
    res.status(400).json({ error: "Elige tu región." });
    return;
  }
  if (!comuna) {
    res.status(400).json({ error: "Escribe tu comuna." });
    return;
  }
  if (body.consent !== true) {
    res.status(400).json({ error: "Debes aceptar recibir el aviso." });
    return;
  }
  if (type === "comercio" && !businessName) {
    res.status(400).json({ error: "Cuéntanos el nombre de tu local." });
    return;
  }

  const id = createHash("sha256").update(email).digest("hex").slice(0, 40);
  try {
    await getFirestore().collection("waitlist").doc(id).create({
      name,
      email,
      type,
      region,
      comuna,
      businessName,
      consent: true,
      source: req.get("origin") ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });
    res.json({ ok: true, already: false });
  } catch (e) {
    // ALREADY_EXISTS: el correo ya estaba inscrito.
    if ((e as { code?: number }).code === 6) {
      res.json({ ok: true, already: true });
      return;
    }
    throw e;
  }
});
