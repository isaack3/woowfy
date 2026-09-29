import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

/**
 * El cliente califica un pedido ya retirado (1–5 estrellas y comentario opcional).
 * Una calificación por pedido (reviews/{orderId}); la nota del local se actualiza en la misma transacción
 * y onStoreUpdated la copia a sus bolsas vigentes.
 */
export const rateOrder = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const orderId = String(req.data?.orderId ?? "");
  const rating = Number(req.data?.rating);
  const comment = String(req.data?.comment ?? "").trim().slice(0, 500);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "La calificación va de 1 a 5 estrellas.");
  }

  const db = getFirestore();
  const orderRef = db.collection("orders").doc(orderId);
  const reviewRef = db.collection("reviews").doc(orderId);
  await db.runTransaction(async (tx) => {
    const order = (await tx.get(orderRef)).data();
    if (!order || order.userUid !== uid) throw new HttpsError("not-found", "Pedido no encontrado.");
    if (order.status !== "picked_up") throw new HttpsError("failed-precondition", "Solo puedes calificar pedidos retirados.");
    if ((await tx.get(reviewRef)).exists) throw new HttpsError("already-exists", "Ya calificaste este pedido.");
    const storeRef = db.collection("stores").doc(order.storeId);
    const store = (await tx.get(storeRef)).data() ?? {};
    const user = (await tx.get(db.collection("users").doc(uid))).data() ?? {};

    const count = (store.ratingCount ?? 0) + 1;
    const sum = (store.ratingSum ?? 0) + rating;
    tx.create(reviewRef, {
      orderId,
      storeId: order.storeId,
      // Las opiniones son públicas: solo el nombre de pila, sin identificadores de la cuenta.
      userName: String(user.name ?? "").trim().split(/\s+/)[0] || "Cliente",
      bagTitle: order.bagTitle,
      rating,
      comment,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(orderRef, { rating });
    tx.update(storeRef, { ratingCount: count, ratingSum: sum, ratingAvg: Math.round((sum / count) * 10) / 10 });
  });
  return { ok: true };
});
