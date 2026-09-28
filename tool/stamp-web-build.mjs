// Se ejecuta antes de cada deploy de la app (predeploy en firebase.json).
// Flutter genera siempre "main.dart.js" con el mismo nombre; si el navegador lo tiene en caché
// seguiría usando la versión anterior. Agregamos ?v=<hash del contenido> para que cada versión
// tenga una URL distinta y se descargue sí o sí.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const dir = process.argv[2] ?? "build/web";
const main = readFileSync(`${dir}/main.dart.js`);
const v = createHash("sha256").update(main).digest("hex").slice(0, 12);

const file = `${dir}/flutter_bootstrap.js`;
const src = readFileSync(file, "utf8");
const out = src.replace(/"mainJsPath":"main\.dart\.js(\?v=[a-f0-9]+)?"/, `"mainJsPath":"main.dart.js?v=${v}"`);
if (out === src && !src.includes(`main.dart.js?v=${v}`)) {
  console.error("stamp-web-build: no encontré mainJsPath en flutter_bootstrap.js");
  process.exit(1);
}
writeFileSync(file, out);
console.log(`stamp-web-build: main.dart.js?v=${v}`);
