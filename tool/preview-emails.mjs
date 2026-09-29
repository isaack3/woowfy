// Genera los correos de ejemplo como HTML para revisarlos en el navegador (no envía nada).
// Uso: npm --prefix functions run build && node tool/preview-emails.mjs  →  build/emails/*.html
import { mkdirSync, writeFileSync } from "node:fs";
import { _templates as t } from "../functions/lib/email.js";

const out = new URL("../build/emails/", import.meta.url);
mkdirSync(out, { recursive: true });
const order = t.sampleOrder();
const mails = {
  bienvenida: t.welcomeEmail({ name: "Camila", type: "cliente" }),
  compra: t.purchaseEmail(order),
  "reembolso-local": t.refundEmail(order),
  "reembolso-cliente": t.refundEmail({ ...order, cancelReason: "customer" }),
};
for (const [name, { subject, html }] of Object.entries(mails)) {
  writeFileSync(new URL(`${name}.html`, out), html);
  console.log(`${name}.html  —  ${subject}`);
}
