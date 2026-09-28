// Aplica storage-cors.json al bucket de Firebase Storage (sin necesitar gsutil).
// Uso: node tool/set-storage-cors.mjs   (requiere haber hecho `firebase login`)
// Sin CORS, la app web de Flutter no puede mostrar las fotos subidas (logos y bolsas).
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

const require = createRequire(import.meta.url);
const lib = join(process.env.APPDATA ?? join(process.env.HOME, ".npm-global"), "npm/node_modules/firebase-tools/lib") + "/";
const { configstore } = require(lib + "configstore");
const auth = require(lib + "auth");

const BUCKET = "woowfy-app.firebasestorage.app";
const cors = JSON.parse(readFileSync(new URL("../storage-cors.json", import.meta.url), "utf8"));
const { access_token } = await auth.getAccessToken(configstore.get("tokens").refresh_token, []);
const res = await fetch(`https://storage.googleapis.com/storage/v1/b/${BUCKET}?fields=cors`, {
  method: "PATCH",
  headers: { Authorization: `Bearer ${access_token}`, "Content-Type": "application/json" },
  body: JSON.stringify({ cors }),
});
const body = await res.json();
console.log(res.status, JSON.stringify(body.cors ?? body));
