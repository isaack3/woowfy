// SOLO LECTURA. Revisa si en producción quedan datos sensibles de antes de la auditoría del 28-09
// (AUDITORIA-2026-09-28.md, hallazgo #10): códigos de retiro dentro del pedido (`orders.pickupCode`, que el comercio
// puede leer) y correos de dueños en locales públicos (`stores.ownerEmail`). Solo imprime conteos, nunca valores.
// Uso: node tool/check-legacy-fields.mjs   (requiere haber hecho `firebase login`)
import { createRequire } from "node:module";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const lib = join(process.env.APPDATA ?? join(process.env.HOME, ".npm-global"), "npm/node_modules/firebase-tools/lib") + "/";
const { configstore } = require(lib + "configstore");
const auth = require(lib + "auth");

const BASE = "https://firestore.googleapis.com/v1/projects/woowfy-app/databases/(default)/documents";
const { access_token } = await auth.getAccessToken(configstore.get("tokens").refresh_token, []);
const headers = { Authorization: `Bearer ${access_token}` };

async function all(collection, fields) {
  const docs = [];
  let page = "";
  do {
    const mask = fields.map((f) => `mask.fieldPaths=${f}`).join("&");
    const r = await fetch(`${BASE}/${collection}?pageSize=300&${mask}${page ? `&pageToken=${page}` : ""}`, { headers })
      .then((x) => x.json());
    if (r.error) throw new Error(`${collection}: ${r.error.message}`);
    docs.push(...(r.documents ?? []));
    page = r.nextPageToken ?? "";
  } while (page);
  return docs;
}

const orders = await all("orders", ["status", "pickupCode", "pickupEnd"]);
const stores = await all("stores", ["ownerEmail"]);
const legacy = orders.filter((o) => o.fields?.pickupCode);
const stillRedeemable = legacy.filter((o) => o.fields?.status?.stringValue === "paid"
  && Date.parse(o.fields?.pickupEnd?.timestampValue ?? 0) + 60 * 60_000 > Date.now());

console.log(`Pedidos: ${orders.length}`);
console.log(`  con pickupCode dentro del pedido (el comercio lo puede leer): ${legacy.length}`);
console.log(`  de esos, todavía retirables (pagados y dentro del horario):     ${stillRedeemable.length}`);
console.log(`Locales: ${stores.length}`);
console.log(`  con ownerEmail (público si el local está aprobado):              ${stores.filter((s) => s.fields?.ownerEmail).length}`);
