// Carga datos de prueba en los EMULADORES locales (nunca en producción).
// Uso (con los emuladores corriendo):  npm --prefix functions run seed
//
// Cuentas de prueba (solo existen en el emulador):
//   comercio@woowfy.test / woowfy-test   → dueño de "Panadería La Espiga" (aprobado)
//   cliente@woowfy.test  / woowfy-test   → cliente
//   cafe@woowfy.test     / woowfy-test   → dueño de "Café del Barrio" (solicitud pendiente)
//   admin@woowfy.test    / woowfy-test   → administrador (/admin)
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
// Evita que firebase-admin busque credenciales de Google Cloud (MetadataLookupWarning).
process.env.GOOGLE_CLOUD_PROJECT ??= "woowfy-app";
process.env.METADATA_SERVER_DETECTION ??= "none";

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { readFileSync } from "node:fs";

initializeApp({ projectId: "woowfy-app", storageBucket: "woowfy-app.firebasestorage.app" });
const auth = getAuth();
const db = getFirestore();
const PASSWORD = "woowfy-test";

async function user(email, role) {
  const u = await auth.getUserByEmail(email).catch(() => auth.createUser({ email, password: PASSWORD }));
  await db.doc(`users/${u.uid}`).set({ email, role, createdAt: FieldValue.serverTimestamp() });
  return u.uid;
}

const merchantUid = await user("comercio@woowfy.test", "customer");
await user("cliente@woowfy.test", "customer");
await user("admin@woowfy.test", "admin");
const cafeUid = await user("cafe@woowfy.test", "customer");
await db.doc("stores/demo-cafe").set({
  ownerUid: cafeUid,
  ownerEmail: "cafe@woowfy.test",
  name: "Café del Barrio",
  category: "Café",
  comuna: "Ñuñoa",
  region: "Metropolitana de Santiago",
  address: "Irarrázaval 2500",
  phone: "+56 9 1111 2222",
  status: "pending",
  createdAt: FieldValue.serverTimestamp(),
});

const store = {
  ownerUid: merchantUid,
  name: "Panadería La Espiga",
  category: "Panadería",
  description: "Pan de masa madre y pastelería artesanal.",
  hours: "Lun a sáb, 8:00 – 21:00",
  comuna: "Providencia",
  region: "Metropolitana de Santiago",
  address: "Av. Providencia 1234",
  ownerEmail: "comercio@woowfy.test",
  phone: "+56 9 3333 4444",
  status: "approved",
  createdAt: FieldValue.serverTimestamp(),
};
await db.doc("stores/demo-espiga").set(store);

// Foto de ejemplo para una bolsa (la otra queda sin foto para ver el ícono de "sin imagen").
let sampleUrl = null;
try {
  const path = "uploads/demo/bags/demo.png";
  await getStorage().bucket().file(path).save(readFileSync(new URL("../../brand/04-social-og/instagram-1080x1080.png", import.meta.url)), { contentType: "image/png" });
  sampleUrl = "http://127.0.0.1:9199/v0/b/woowfy-app.firebasestorage.app/o/" + encodeURIComponent(path) + "?alt=media";
} catch {
  console.log("(Emulador de Storage no disponible: la bolsa de ejemplo queda sin foto)");
}

const now = Date.now();
const bags = [
  { id: "demo-pan", title: "Bolsa panadería", originalPrice: 9000, price: 3490, quantityAvailable: 4, imageUrl: sampleUrl },
  { id: "demo-dulce", title: "Bolsa dulces", originalPrice: 12000, price: 4490, quantityAvailable: 2 },
];
for (const b of bags) {
  await db.doc(`bags/${b.id}`).set({
    storeId: "demo-espiga",
    storeName: store.name,
    comuna: store.comuna,
    region: store.region,
    category: store.category,
    address: store.address,
    title: b.title,
    description: "Pan y bollería del día. El contenido varía.",
    originalPrice: b.originalPrice,
    price: b.price,
    quantityAvailable: b.quantityAvailable,
    pickupStart: Timestamp.fromMillis(now),
    pickupEnd: Timestamp.fromMillis(now + 3 * 60 * 60 * 1000),
    active: true,
    ...(b.imageUrl ? { imageUrl: b.imageUrl } : {}),
    createdAt: FieldValue.serverTimestamp(),
  });
}
for (const w of [
  { id: "demo-wl-1", name: "Camila Rojas", email: "vecina@ejemplo.cl", type: "cliente", region: "Metropolitana de Santiago", comuna: "Ñuñoa", businessName: null },
  { id: "demo-wl-2", name: "Pedro Soto", email: "pasteleria@ejemplo.cl", type: "comercio", region: "Valparaíso", comuna: "Viña del Mar", businessName: "Pastelería Dulce" },
]) {
  const { id, ...data } = w;
  await db.doc(`waitlist/${id}`).set({ ...data, consent: true, source: "seed", createdAt: FieldValue.serverTimestamp() });
}
await db.doc("config/email").set({ enabled: false, fromName: "Woowfy", fromEmail: "hola@woowfy.com", replyTo: null });
console.log("Datos de prueba cargados en los emuladores.");
