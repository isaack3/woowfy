import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

/** Máximo de pedidos por liquidación (una transacción admite 500 escrituras). */
const MAX_ORDERS_PER_PAYOUT = 450;
/** Estados que se le pagan al local: retirado, o no retirado por el cliente (la bolsa se apartó igual). */
const PAYABLE_STATUSES = ["picked_up", "no_show"];

type PayoutResult = { payoutId: string; storeId: string; storeName: string; orderCount: number; storeAmount: number };

async function requireAdmin(uid: string | undefined): Promise<string> {
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const me = (await getFirestore().collection("users").doc(uid).get()).data();
  if (me?.role !== "admin") throw new HttpsError("permission-denied", "Solo administradores.");
  return uid;
}

/**
 * Liquida las ventas pendientes de un local. Todo en una transacción: si dos liquidaciones corren a la vez (doble
 * clic, dos admins), la segunda se reintenta y ya no encuentra pedidos sin liquidar. Devuelve null si no hay nada.
 */
async function payoutStore(storeId: string, storeName: string, note: string, uid: string): Promise<PayoutResult | null> {
  const db = getFirestore();
  const payoutRef = db.collection("payouts").doc();
  return db.runTransaction(async (tx) => {
    const payable = await tx.get(db.collection("orders").where("storeId", "==", storeId).where("status", "in", PAYABLE_STATUSES));
    const pending = payable.docs.filter((d) => !d.data().payoutId).slice(0, MAX_ORDERS_PER_PAYOUT);
    if (pending.length === 0) return null;

    const totals = pending.reduce(
      (t, d) => {
        const o = d.data();
        return {
          gross: t.gross + o.amount,
          fee: t.fee + (o.platformFee ?? 0),
          store: t.store + (o.storeAmount ?? o.amount),
          noShow: t.noShow + (o.status === "no_show" ? 1 : 0),
        };
      },
      { gross: 0, fee: 0, store: 0, noShow: 0 },
    );
    const dates = pending.map((d) => d.data().pickupStart.toMillis());
    tx.set(payoutRef, {
      storeId,
      storeName,
      orderCount: pending.length,
      noShowCount: totals.noShow,
      grossAmount: totals.gross,
      platformFee: totals.fee,
      storeAmount: totals.store,
      periodFrom: new Date(Math.min(...dates)),
      periodTo: new Date(Math.max(...dates)),
      note,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    pending.forEach((d) => tx.update(d.ref, { payoutId: payoutRef.id }));
    return { payoutId: payoutRef.id, storeId, storeName, orderCount: pending.length, storeAmount: totals.store };
  });
}

/**
 * Liquidaciones: lo que Woowfy le paga a cada comercio.
 * El admin registra un pago (p. ej. una transferencia) y la función marca los pedidos retirados o no retirados que
 * aún no estaban liquidados, guardando el detalle en payouts/{id}. Así el comercio ve qué se le pagó y qué falta.
 */
export const createPayout = onCall(async (req) => {
  const uid = await requireAdmin(req.auth?.uid);
  const storeId = String(req.data?.storeId ?? "");
  const note = String(req.data?.note ?? "").trim().slice(0, 200);
  const store = (await getFirestore().collection("stores").doc(storeId).get()).data();
  if (!store) throw new HttpsError("not-found", "Local no encontrado.");

  const result = await payoutStore(storeId, store.name, note, uid);
  if (!result) throw new HttpsError("failed-precondition", "Este local no tiene ventas por liquidar.");
  return result;
});

/** Liquida de una vez a todos los locales con ventas pendientes (para transferir en lote). */
export const createAllPayouts = onCall(async (req) => {
  const uid = await requireAdmin(req.auth?.uid);
  const note = String(req.data?.note ?? "").trim().slice(0, 200);
  const db = getFirestore();
  // Suficiente para el piloto; con mucho volumen convendría un campo "por liquidar" indexado.
  const payable = await db.collection("orders").where("status", "in", PAYABLE_STATUSES).get();
  const storeIds = [...new Set(payable.docs.filter((d) => !d.data().payoutId).map((d) => d.data().storeId as string))];

  const payouts: PayoutResult[] = [];
  for (const storeId of storeIds) {
    const store = (await db.collection("stores").doc(storeId).get()).data();
    const result = await payoutStore(storeId, store?.name ?? storeId, note, uid);
    if (result) payouts.push(result);
  }
  return { payouts };
});
