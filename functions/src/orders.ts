import { randomInt } from "node:crypto";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { paymentProvider } from "./payments.js";

/** Comisión de Woowfy sobre cada bolsa vendida. Ajustar según validación con comercios. */
const PLATFORM_FEE_RATE = 0.25;
/** Tiempo que la bolsa queda reservada mientras el cliente paga. */
const PAYMENT_TIMEOUT_MINUTES = 15;
/** Margen para validar un retiro después del fin del horario. */
const REDEEM_GRACE_MINUTES = 60;

// Sin caracteres ambiguos (0/O, 1/I/L) para que se pueda dictar o tipear.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

function pickupCode(length = 6): string {
  let code = "";
  for (let i = 0; i < length; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

function requireUid(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  return uid;
}

/** Reserva una unidad de la bolsa, crea la orden y devuelve la URL de pago. */
export const createOrder = onCall(async (req) => {
  const uid = requireUid(req.auth?.uid);
  const bagId = req.data?.bagId;
  if (typeof bagId !== "string" || !bagId) {
    throw new HttpsError("invalid-argument", "Falta la bolsa.");
  }

  const db = getFirestore();
  const orderRef = db.collection("orders").doc();
  const bagRef = db.collection("bags").doc(bagId);

  const order = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bagRef);
    const bag = snap.data();
    const now = Timestamp.now();
    if (!bag || !bag.active || bag.quantityAvailable < 1 || bag.pickupEnd.toMillis() <= now.toMillis()) {
      throw new HttpsError("failed-precondition", "Esta bolsa ya no está disponible.");
    }
    const amount: number = bag.price;
    const platformFee = Math.round(amount * PLATFORM_FEE_RATE);
    const data = {
      userUid: uid,
      bagId,
      storeId: bag.storeId,
      storeName: bag.storeName,
      address: bag.address,
      comuna: bag.comuna,
      bagTitle: bag.title,
      amount,
      platformFee,
      storeAmount: amount - platformFee,
      pickupStart: bag.pickupStart,
      pickupEnd: bag.pickupEnd,
      pickupCode: pickupCode(),
      status: "pending_payment",
      expiresAt: Timestamp.fromMillis(now.toMillis() + PAYMENT_TIMEOUT_MINUTES * 60_000),
      createdAt: FieldValue.serverTimestamp(),
    };
    tx.update(bagRef, { quantityAvailable: FieldValue.increment(-1) });
    tx.set(orderRef, data);
    return data;
  });

  const provider = paymentProvider();
  const checkout = await provider.createCheckout({
    orderId: orderRef.id,
    title: `${order.bagTitle} · ${order.storeName}`,
    amount: order.amount,
    payerEmail: req.auth?.token.email,
  });
  await orderRef.update({
    payment: { provider: provider.name, externalId: checkout.externalId ?? null, checkoutUrl: checkout.url },
  });
  return { orderId: orderRef.id, checkoutUrl: checkout.url };
});

/** Marca la orden como pagada. La usarán tanto el mock como el webhook de Mercado Pago. */
export async function markOrderPaid(orderId: string, externalPaymentId: string): Promise<void> {
  const db = getFirestore();
  const ref = db.collection("orders").doc(orderId);
  await db.runTransaction(async (tx) => {
    const order = (await tx.get(ref)).data();
    if (!order) throw new HttpsError("not-found", "Orden no encontrada.");
    if (order.status !== "pending_payment") return; // idempotente: los webhooks se repiten
    tx.update(ref, {
      status: "paid",
      paidAt: FieldValue.serverTimestamp(),
      "payment.paymentId": externalPaymentId,
    });
  });
}

/** Cancela una orden pendiente y devuelve la unidad al stock de la bolsa. */
export async function cancelPendingOrder(orderId: string, reason: string): Promise<void> {
  const db = getFirestore();
  const ref = db.collection("orders").doc(orderId);
  await db.runTransaction(async (tx) => {
    const order = (await tx.get(ref)).data();
    if (!order || order.status !== "pending_payment") return;
    tx.update(ref, { status: "cancelled", cancelReason: reason, cancelledAt: FieldValue.serverTimestamp() });
    tx.update(db.collection("bags").doc(order.bagId), { quantityAvailable: FieldValue.increment(1) });
  });
}

/** Solo en modo mock: el checkout simulado aprueba o rechaza el pago. */
export const confirmMockPayment = onCall(async (req) => {
  const uid = requireUid(req.auth?.uid);
  if (paymentProvider().name !== "mock") {
    throw new HttpsError("permission-denied", "Pagos simulados deshabilitados.");
  }
  const { orderId, approved } = req.data ?? {};
  if (typeof orderId !== "string" || typeof approved !== "boolean") {
    throw new HttpsError("invalid-argument", "Datos inválidos.");
  }
  const order = (await getFirestore().collection("orders").doc(orderId).get()).data();
  if (!order || order.userUid !== uid) throw new HttpsError("not-found", "Orden no encontrada.");

  if (approved) {
    await markOrderPaid(orderId, `mock_payment_${Date.now()}`);
  } else {
    await cancelPendingOrder(orderId, "payment_rejected");
  }
  return { ok: true };
});

/** El comercio valida el código (o QR) que muestra el cliente al retirar. */
export const redeemOrder = onCall(async (req) => {
  const uid = requireUid(req.auth?.uid);
  const code = String(req.data?.code ?? "").trim().toUpperCase();
  if (code.length !== 6) throw new HttpsError("invalid-argument", "El código tiene 6 caracteres.");

  const db = getFirestore();
  const stores = await db.collection("stores")
    .where("ownerUid", "==", uid).where("status", "==", "approved").limit(1).get();
  if (stores.empty) throw new HttpsError("permission-denied", "No tienes un local aprobado.");
  const storeId = stores.docs[0].id;

  const matches = await db.collection("orders")
    .where("storeId", "==", storeId).where("pickupCode", "==", code).limit(5).get();
  const now = Date.now();
  const doc = matches.docs.find((d) => d.data().status === "paid");
  if (!doc) {
    const redeemed = matches.docs.some((d) => d.data().status === "picked_up");
    throw new HttpsError("not-found", redeemed ? "Este pedido ya fue retirado." : "Código no válido.");
  }
  const order = doc.data();
  if (order.pickupEnd.toMillis() + REDEEM_GRACE_MINUTES * 60_000 < now) {
    throw new HttpsError("failed-precondition", "El horario de retiro de este pedido ya terminó.");
  }

  await db.runTransaction(async (tx) => {
    const fresh = (await tx.get(doc.ref)).data();
    if (fresh?.status !== "paid") throw new HttpsError("aborted", "Este pedido ya fue retirado.");
    tx.update(doc.ref, { status: "picked_up", redeemedAt: FieldValue.serverTimestamp() });
  });
  return { orderId: doc.id, bagTitle: order.bagTitle, amount: order.amount };
});

/**
 * Libera reservas cuyo pago no se completó a tiempo.
 * Corre en São Paulo porque Cloud Scheduler no está disponible en southamerica-west1 (Santiago).
 */
export const expirePendingOrders = onSchedule({
  schedule: "every 5 minutes",
  region: "southamerica-east1",
  timeZone: "America/Santiago",
}, async () => {
  const expired = await getFirestore().collection("orders")
    .where("status", "==", "pending_payment")
    .where("expiresAt", "<", Timestamp.now())
    .limit(200)
    .get();
  await Promise.all(expired.docs.map((d) => cancelPendingOrder(d.id, "payment_timeout")));
});
