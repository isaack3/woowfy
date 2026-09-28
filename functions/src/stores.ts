import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { geocode } from "./geo.js";

/** Datos del local que se copian a sus bolsas (para mostrarlos sin leer el local). */
const COPIED = ["name", "logoUrl", "category", "address", "comuna", "region", "lat", "lng"] as const;
const BAG_FIELD: Record<(typeof COPIED)[number], string> = {
  name: "storeName",
  logoUrl: "storeLogoUrl",
  category: "category",
  address: "address",
  comuna: "comuna",
  region: "region",
  lat: "lat",
  lng: "lng",
};

const addressChanged = (a: FirebaseFirestore.DocumentData, b: FirebaseFirestore.DocumentData) =>
  a.address !== b.address || a.comuna !== b.comuna || a.region !== b.region;

/** Al crear un local, calcula sus coordenadas a partir de la dirección (para el mapa y "cerca de mí"). */
export const onStoreCreated = onDocumentCreated("stores/{storeId}", async (event) => {
  const s = event.data?.data();
  if (!s) return;
  const pos = await geocode(s.address, s.comuna, s.region);
  if (pos) await event.data!.ref.update(pos);
});

/** Cuando el comercio edita su perfil: recalcula coordenadas si cambió la dirección y actualiza sus bolsas vigentes. */
export const onStoreUpdated = onDocumentUpdated("stores/{storeId}", async (event) => {
  const before = event.data?.before.data() ?? {};
  const after = event.data?.after.data() ?? {};

  // Nueva dirección → nuevas coordenadas. Este update vuelve a disparar la función y ahí se copian a las bolsas.
  if (addressChanged(before, after)) {
    const pos = await geocode(after.address, after.comuna, after.region);
    if (pos && (pos.lat !== after.lat || pos.lng !== after.lng)) {
      await event.data!.after.ref.update(pos);
    }
  }

  const changes: Record<string, unknown> = {};
  for (const k of COPIED) {
    if (before[k] !== after[k]) changes[BAG_FIELD[k]] = after[k] ?? null;
  }
  if (Object.keys(changes).length === 0) return;

  const db = getFirestore();
  const bags = await db.collection("bags")
    .where("storeId", "==", event.params.storeId)
    .where("pickupEnd", ">=", Timestamp.now())
    .get();
  const batch = db.batch();
  bags.docs.forEach((d) => batch.update(d.ref, changes));
  await batch.commit();
});
