import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

/**
 * Liquidaciones: lo que Woowfy le paga a cada comercio.
 * El admin registra un pago (p. ej. una transferencia) y la función marca todos los pedidos retirados que aún no
 * estaban liquidados, guardando el detalle en payouts/{id}. Así el comercio ve qué se le pagó y qué queda pendiente.
 */
export const createPayout = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const db = getFirestore();
  const me = (await db.collection("users").doc(uid).get()).data();
  if (me?.role !== "admin") throw new HttpsError("permission-denied", "Solo administradores.");

  const storeId = String(req.data?.storeId ?? "");
  const note = String(req.data?.note ?? "").trim().slice(0, 200);
  const store = (await db.collection("stores").doc(storeId).get()).data();
  if (!store) throw new HttpsError("not-found", "Local no encontrado.");

  const picked = await db.collection("orders").where("storeId", "==", storeId).where("status", "==", "picked_up").get();
  const pending = picked.docs.filter((d) => !d.data().payoutId);
  if (pending.length === 0) throw new HttpsError("failed-precondition", "Este local no tiene ventas por liquidar.");

  const totals = pending.reduce(
    (t, d) => {
      const o = d.data();
      return { gross: t.gross + o.amount, fee: t.fee + (o.platformFee ?? 0), store: t.store + (o.storeAmount ?? o.amount) };
    },
    { gross: 0, fee: 0, store: 0 },
  );
  const payoutRef = db.collection("payouts").doc();
  const dates = pending.map((d) => d.data().pickupStart.toMillis());
  await payoutRef.set({
    storeId,
    storeName: store.name,
    orderCount: pending.length,
    grossAmount: totals.gross,
    platformFee: totals.fee,
    storeAmount: totals.store,
    periodFrom: new Date(Math.min(...dates)),
    periodTo: new Date(Math.max(...dates)),
    note,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  for (let i = 0; i < pending.length; i += 450) {
    const batch = db.batch();
    pending.slice(i, i + 450).forEach((d) => batch.update(d.ref, { payoutId: payoutRef.id }));
    await batch.commit();
  }
  return { payoutId: payoutRef.id, orderCount: pending.length, storeAmount: totals.store };
});
