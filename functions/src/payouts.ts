import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

/** Máximo de pedidos por liquidación (una transacción admite 500 escrituras). */
const MAX_ORDERS_PER_PAYOUT = 450;
/** Estados que se le pagan al local: retirado, o no retirado por el cliente (la bolsa se apartó igual). */
const PAYABLE_STATUSES = ["picked_up", "no_show"];

type PayoutResult = { payoutId: string; storeId: string; storeName: string; orderCount: number; storeAmount: number };

/** Un local sin cuenta bancaria no se liquida: no habría a dónde transferirle. */
async function hasBankAccount(storeId: string): Promise<boolean> {
  const bank = await getFirestore().collection("stores").doc(storeId).collection("private").doc("bank").get();
  return bank.exists && Boolean(bank.data()?.accountNumber);
}

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
/** Cuenta de destino tal como estaba al liquidar: el historial no debe cambiar si el local cambia de cuenta. */
async function bankSnapshot(storeId: string): Promise<Record<string, string> | null> {
  const d = (await getFirestore().collection("stores").doc(storeId).collection("private").doc("bank").get()).data();
  if (!d) return null;
  const pick = (k: string) => (typeof d[k] === "string" ? d[k] : "");
  return {
    holder: pick("holder"), rut: pick("rut"), bank: pick("bank"),
    accountType: pick("accountType"), accountNumber: pick("accountNumber"), email: pick("email"),
  };
}

async function payoutStore(storeId: string, storeName: string, note: string, uid: string): Promise<PayoutResult | null> {
  const db = getFirestore();
  const destination = await bankSnapshot(storeId);
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
      destination,
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
  if (!(await hasBankAccount(storeId))) {
    throw new HttpsError("failed-precondition", "Este local aún no registra su cuenta bancaria.");
  }

  const result = await payoutStore(storeId, store.name, note, uid);
  if (!result) throw new HttpsError("failed-precondition", "Este local no tiene ventas por liquidar.");
  return result;
});

/**
 * Liquida de una vez a los locales con ventas pendientes (para transferir en lote). Si se pasa storeIds, solo a
 * esos (los que el admin revisó en la vista previa). Los locales sin cuenta bancaria quedan fuera y se informan.
 */
export const createAllPayouts = onCall(async (req) => {
  const uid = await requireAdmin(req.auth?.uid);
  const note = String(req.data?.note ?? "").trim().slice(0, 200);
  const db = getFirestore();
  // Suficiente para el piloto; con mucho volumen convendría un campo "por liquidar" indexado.
  const payable = await db.collection("orders").where("status", "in", PAYABLE_STATUSES).get();
  const requested = Array.isArray(req.data?.storeIds) ? new Set((req.data.storeIds as unknown[]).map(String)) : null;
  const storeIds = [...new Set(payable.docs.filter((d) => !d.data().payoutId).map((d) => d.data().storeId as string))]
    .filter((id) => !requested || requested.has(id));

  const payouts: PayoutResult[] = [];
  const skipped: { storeId: string; storeName: string }[] = [];
  for (const storeId of storeIds) {
    const store = (await db.collection("stores").doc(storeId).get()).data();
    const storeName = store?.name ?? storeId;
    if (!(await hasBankAccount(storeId))) {
      skipped.push({ storeId, storeName });
      continue;
    }
    const result = await payoutStore(storeId, storeName, note, uid);
    if (result) payouts.push(result);
  }
  return { payouts, skipped };
});

/**
 * Anula una liquidación registrada por error (p. ej. la transferencia no se hizo): sus ventas vuelven a quedar
 * por pagar y la liquidación queda en el historial marcada como anulada, con el motivo.
 */
export const voidPayout = onCall(async (req) => {
  const uid = await requireAdmin(req.auth?.uid);
  const payoutId = String(req.data?.payoutId ?? "");
  const reason = String(req.data?.reason ?? "").trim().slice(0, 200);
  if (!payoutId) throw new HttpsError("invalid-argument", "Falta la liquidación.");
  const db = getFirestore();
  const ref = db.collection("payouts").doc(payoutId);
  return db.runTransaction(async (tx) => {
    const payout = await tx.get(ref);
    if (!payout.exists) throw new HttpsError("not-found", "Liquidación no encontrada.");
    if (payout.data()?.voidedAt) throw new HttpsError("failed-precondition", "Esta liquidación ya estaba anulada.");
    const orders = await tx.get(db.collection("orders").where("payoutId", "==", payoutId));
    orders.docs.forEach((d) => tx.update(d.ref, { payoutId: FieldValue.delete() }));
    tx.update(ref, { voidedAt: FieldValue.serverTimestamp(), voidedBy: uid, voidReason: reason });
    return { orderCount: orders.size };
  });
});
