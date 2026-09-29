import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions/v2";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

const APP = "https://app.woowfy.com";

/**
 * Envía una notificación push web a todos los dispositivos del usuario (users/{uid}.fcmTokens)
 * y limpia los tokens que ya no sirven.
 */
export async function pushToUser(uid: string, title: string, body: string, link: string): Promise<number> {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}`);
  const tokens: string[] = (await ref.get()).data()?.fcmTokens ?? [];
  if (tokens.length === 0) return 0;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    webpush: {
      fcmOptions: { link: `${APP}${link}` },
      notification: { icon: `${APP}/icons/Icon-192.png`, badge: `${APP}/icons/Icon-192.png` },
    },
  });
  const dead = res.responses
    .map((r, i) => (!r.success && ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"]
      .includes(r.error?.code ?? "") ? tokens[i] : null))
    .filter((t): t is string => t !== null);
  if (dead.length) await ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  return res.successCount;
}

/** Un local publica una bolsa → avisa a quienes lo tienen en favoritos. */
export const onBagCreated = onDocumentCreated("bags/{bagId}", async (event) => {
  const bag = event.data?.data();
  if (!bag) return;
  // La nota del local la pone el servidor (las reglas no dejan que el comercio la escriba).
  const store = (await getFirestore().doc(`stores/${bag.storeId}`).get()).data();
  if (store?.ratingCount) {
    await event.data!.ref.update({ storeRatingAvg: store.ratingAvg, storeRatingCount: store.ratingCount });
  }
  if (!bag.active) return;
  const favs = await getFirestore().collectionGroup("favorites").where("storeId", "==", bag.storeId).get();
  let sent = 0;
  for (const f of favs.docs) {
    const uid = f.ref.parent.parent!.id;
    sent += await pushToUser(uid, `${bag.storeName} publicó una bolsa`, `${bag.title} a $${Number(bag.price).toLocaleString("es-CL")}. ¡Resérvala antes de que se agote!`, `/bag/${event.params.bagId}`);
  }
  if (favs.size) logger.info(`Aviso de favoritos: ${favs.size} seguidores, ${sent} notificaciones enviadas`);
});

/** Cada 15 minutos: recuerda el retiro a quienes tienen un pedido pagado que empieza en los próximos 45 minutos. */
export const sendPickupReminders = onSchedule({
  schedule: "every 15 minutes",
  region: "southamerica-east1", // Cloud Scheduler no existe en Santiago
}, async () => {
  const now = Date.now();
  const db = getFirestore();
  const orders = await db.collection("orders")
    .where("status", "==", "paid")
    .where("pickupStart", "<=", Timestamp.fromMillis(now + 45 * 60_000))
    // Sin límite inferior, cada corrida revisaría todos los pedidos pagados que nunca se retiraron.
    .where("pickupStart", ">=", Timestamp.fromMillis(now - 3 * 3600_000))
    .get();
  let sent = 0;
  for (const d of orders.docs) {
    const o = d.data();
    if (o.reminderSentAt || o.pickupEnd.toMillis() < now) continue;
    const time = new Intl.DateTimeFormat("es-CL", { timeZone: "America/Santiago", hour: "2-digit", minute: "2-digit" })
      .format(o.pickupStart.toDate());
    sent += await pushToUser(o.userUid, `Tu bolsa de ${o.storeName} te espera`, `Retiro desde las ${time} en ${o.address}. Lleva tu código QR.`, `/order/${d.id}`);
    await d.ref.update({ reminderSentAt: FieldValue.serverTimestamp() });
  }
  if (sent) logger.info(`Recordatorios de retiro enviados: ${sent}`);
});
