// Calcula coordenadas (lat/lng) para los locales que aún no las tienen, con la misma geocodificación
// que usan las funciones. Al guardarlas, onStoreUpdated las copia a sus bolsas vigentes.
// Uso: npm --prefix functions run build && node tool/backfill-store-coords.mjs
import { createRequire } from "node:module";
import { join } from "node:path";
import { geocode } from "../functions/lib/geo.js";

const require = createRequire(import.meta.url);
const lib = join(process.env.APPDATA, "npm/node_modules/firebase-tools/lib") + "/";
const { configstore } = require(lib + "configstore");
const auth = require(lib + "auth");

const BASE = "https://firestore.googleapis.com/v1/projects/woowfy-app/databases/(default)/documents";
const { access_token } = await auth.getAccessToken(configstore.get("tokens").refresh_token, []);
const h = { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" };
const { documents = [] } = await fetch(`${BASE}/stores?pageSize=300`, { headers: h }).then((r) => r.json());

for (const d of documents) {
  const f = d.fields;
  const name = f.name?.stringValue;
  if (f.lat) { console.log(`= ${name}: ya tiene coordenadas`); continue; }
  const pos = await geocode(f.address?.stringValue ?? "", f.comuna?.stringValue ?? "", f.region?.stringValue ?? "");
  if (!pos) { console.log(`✗ ${name}: no se encontró la dirección`); continue; }
  const r = await fetch(`https://firestore.googleapis.com/v1/${d.name}?updateMask.fieldPaths=lat&updateMask.fieldPaths=lng`, {
    method: "PATCH", headers: h, body: JSON.stringify({ fields: { lat: { doubleValue: pos.lat }, lng: { doubleValue: pos.lng } } }),
  });
  console.log(`${r.ok ? "✓" : "✗"} ${name}: ${pos.lat}, ${pos.lng}`);
  await new Promise((res) => setTimeout(res, 1100)); // política de uso de Nominatim
}
