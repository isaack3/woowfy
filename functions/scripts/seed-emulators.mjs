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
// Evita que firebase-admin busque credenciales de Google Cloud (MetadataLookupWarning).
process.env.GOOGLE_CLOUD_PROJECT ??= "woowfy-app";
process.env.METADATA_SERVER_DETECTION ??= "none";

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";

initializeApp({ projectId: "woowfy-app" });
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
  comuna: "Ñuñoa",
  address: "Irarrázaval 2500",
  phone: "+56 9 1111 2222",
  status: "pending",
  createdAt: FieldValue.serverTimestamp(),
});

const store = {
  ownerUid: merchantUid,
  name: "Panadería La Espiga",
  comuna: "Providencia",
  address: "Av. Providencia 1234",
  ownerEmail: "comercio@woowfy.test",
  phone: "+56 9 3333 4444",
  status: "approved",
  createdAt: FieldValue.serverTimestamp(),
};
await db.doc("stores/demo-espiga").set(store);

const now = Date.now();
const bags = [
  { id: "demo-pan", title: "Bolsa panadería", originalPrice: 9000, price: 3490, quantityAvailable: 4 },
  { id: "demo-dulce", title: "Bolsa dulces", originalPrice: 12000, price: 4490, quantityAvailable: 2 },
];
for (const b of bags) {
  await db.doc(`bags/${b.id}`).set({
    storeId: "demo-espiga",
    storeName: store.name,
    comuna: store.comuna,
    address: store.address,
    title: b.title,
    description: "Pan y bollería del día. El contenido varía.",
    originalPrice: b.originalPrice,
    price: b.price,
    quantityAvailable: b.quantityAvailable,
    pickupStart: Timestamp.fromMillis(now),
    pickupEnd: Timestamp.fromMillis(now + 3 * 60 * 60 * 1000),
    active: true,
    createdAt: FieldValue.serverTimestamp(),
  });
}
console.log("Datos de prueba cargados en los emuladores.");
