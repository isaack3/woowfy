import { randomInt } from "node:crypto";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { pushToUser } from "./notifications.js";
import { mercadoPago, PAYMENT_SECRETS, paymentProvider, validMercadoPagoSignature } from "./payments.js";

/** Comisión de Woowfy sobre cada bolsa vendida. Ajustar según validación con comercios. */
const PLATFORM_FEE_RATE = 0.25;
/** Tiempo que la bolsa queda reservada mientras el cliente paga. */
const PAYMENT_TIMEOUT_MINUTES = 15;
/** Margen para validar un retiro después del fin del horario. */
const REDEEM_GRACE_MINUTES = 60;
/** El cliente puede cancelar (con reembolso) hasta estas horas antes del inicio del retiro (ver /terms). */
export const CANCEL_HOURS_BEFORE = 2;

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
export const createOrder = onCall({ secrets: PAYMENT_SECRETS }, async (req) => {
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
      imageUrl: bag.imageUrl ?? null,
      amount,
      originalPrice: bag.originalPrice,
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
    expiresAt: order.expiresAt.toDate(),
  });
  await orderRef.update({
    payment: { provider: provider.name, externalId: checkout.externalId ?? null, checkoutUrl: checkout.url },
  });
  return { orderId: orderRef.id, checkoutUrl: checkout.url };
});

/**
 * Marca la orden como pagada. La usan el mock y el webhook de Mercado Pago.
 * Devuelve "late" si el pago llegó cuando la reserva ya había vencido (hay que reembolsarlo).
 */
export async function markOrderPaid(orderId: string, externalPaymentId: string): Promise<"paid" | "late" | "noop"> {
  const db = getFirestore();
  const ref = db.collection("orders").doc(orderId);
  return db.runTransaction(async (tx) => {
    const order = (await tx.get(ref)).data();
    if (!order) throw new HttpsError("not-found", "Orden no encontrada.");
    if (order.status === "pending_payment") {
      tx.update(ref, { status: "paid", paidAt: FieldValue.serverTimestamp(), "payment.paymentId": externalPaymentId });
      return "paid";
    }
    // Pagó después de que venció la reserva: se registra el pago para reembolsarlo.
    if (order.status === "cancelled" && !order.payment?.paymentId) {
      tx.update(ref, { "payment.paymentId": externalPaymentId });
      return "late";
    }
    return "noop"; // idempotente: los webhooks se repiten
  });
}

/** Reembolsa un pedido cancelado que ya estaba pagado y deja registro del resultado. */
async function refundOrder(orderId: string): Promise<void> {
  const ref = getFirestore().collection("orders").doc(orderId);
  const order = (await ref.get()).data();
  const paymentId = order?.payment?.paymentId;
  if (!order || !paymentId || order.refund?.status === "done") return;
  try {
    const refundId = await paymentProvider().refund(paymentId, orderId);
    await ref.update({ refund: { status: "done", id: refundId, amount: order.amount, at: FieldValue.serverTimestamp() } });
  } catch (e) {
    logger.error("Reembolso falló", orderId, e);
    await ref.update({ refund: { status: "error", error: String((e as Error).message).slice(0, 300), amount: order.amount } });
  }
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

/** El cliente cancela su pedido: gratis si está pendiente de pago; con reembolso si falta tiempo para el retiro. */
export const cancelOrder = onCall({ secrets: PAYMENT_SECRETS }, async (req) => {
  const uid = requireUid(req.auth?.uid);
  const orderId = String(req.data?.orderId ?? "");
  const db = getFirestore();
  const ref = db.collection("orders").doc(orderId);
  const order = (await ref.get()).data();
  if (!order || order.userUid !== uid) throw new HttpsError("not-found", "Pedido no encontrado.");

  if (order.status === "pending_payment") {
    await cancelPendingOrder(orderId, "customer");
    return { refunded: false };
  }
  if (order.status !== "paid") throw new HttpsError("failed-precondition", "Este pedido ya no se puede cancelar.");
  const limit = order.pickupStart.toMillis() - CANCEL_HOURS_BEFORE * 3600_000;
  if (Date.now() > limit) {
    throw new HttpsError("failed-precondition",
      `Solo puedes cancelar hasta ${CANCEL_HOURS_BEFORE} horas antes del inicio del retiro.`);
  }
  await db.runTransaction(async (tx) => {
    const fresh = (await tx.get(ref)).data();
    if (fresh?.status !== "paid") throw new HttpsError("aborted", "Este pedido ya no se puede cancelar.");
    tx.update(ref, {
      status: "cancelled", cancelReason: "customer", cancelledAt: FieldValue.serverTimestamp(),
      refund: { status: "pending", amount: fresh.amount },
    });
    tx.update(db.collection("bags").doc(fresh.bagId), { quantityAvailable: FieldValue.increment(1) });
  });
  await refundOrder(orderId);
  return { refunded: true };
});

/** El comercio cancela la bolsa del día: se despublica, se reembolsa a quienes pagaron y se les avisa. */
export const cancelBag = onCall({ secrets: PAYMENT_SECRETS }, async (req) => {
  const uid = requireUid(req.auth?.uid);
  const bagId = String(req.data?.bagId ?? "");
  const reason = String(req.data?.reason ?? "").trim().slice(0, 200) || "El local tuvo un imprevisto.";
  const db = getFirestore();
  const bagRef = db.collection("bags").doc(bagId);
  const bag = (await bagRef.get()).data();
  if (!bag) throw new HttpsError("not-found", "Bolsa no encontrada.");
  const store = (await db.collection("stores").doc(bag.storeId).get()).data();
  if (store?.ownerUid !== uid || store?.status !== "approved") throw new HttpsError("permission-denied", "No es tu bolsa.");

  await bagRef.update({ active: false, quantityAvailable: 0, cancelledAt: FieldValue.serverTimestamp(), cancelReason: reason });
  const orders = await db.collection("orders").where("bagId", "==", bagId)
    .where("status", "in", ["pending_payment", "paid"]).get();
  let refunded = 0;
  for (const d of orders.docs) {
    const o = d.data();
    const wasPaid = o.status === "paid";
    await d.ref.update({
      status: "cancelled", cancelReason: "store", storeMessage: reason, cancelledAt: FieldValue.serverTimestamp(),
      ...(wasPaid ? { refund: { status: "pending", amount: o.amount } } : {}),
    });
    if (wasPaid) {
      await refundOrder(d.id);
      refunded++;
      await pushToUser(o.userUid, `${o.storeName} canceló tu bolsa`,
        `${reason} Te devolvimos $${Number(o.amount).toLocaleString("es-CL")}.`, `/order/${d.id}`);
    }
  }
  return { cancelledOrders: orders.size, refunded };
});

/**
 * Webhook de Mercado Pago: confirma o rechaza pagos. Verifica la firma y luego consulta el pago a la API
 * (nunca confía en el contenido del aviso). Es idempotente: Mercado Pago reintenta los avisos.
 */
export const mercadoPagoWebhook = onRequest({ secrets: PAYMENT_SECRETS }, async (req, res) => {
  const type = String(req.query.type ?? req.body?.type ?? req.query.topic ?? "");
  const dataId = String(req.query["data.id"] ?? req.body?.data?.id ?? req.query.id ?? "");
  if (type !== "payment" || !dataId) {
    res.status(200).send("ignorado");
    return;
  }
  if (!validMercadoPagoSignature(req.get("x-signature"), req.get("x-request-id"), dataId)) {
    // Diagnóstico sin secretos: qué formato de notificación llegó y con qué encabezados.
    logger.warn("Webhook de Mercado Pago con firma inválida", {
      dataId,
      query: Object.keys(req.query),
      bodyType: req.body?.type ?? null,
      bodyAction: req.body?.action ?? null,
      hasSignature: Boolean(req.get("x-signature")),
      hasRequestId: Boolean(req.get("x-request-id")),
      signatureKeys: (req.get("x-signature") ?? "").split(",").map((p) => p.trim().split("=")[0]),
    });
    res.status(401).send("firma inválida");
    return;
  }
  let payment;
  try {
    payment = await mercadoPago().getPayment(dataId);
  } catch (e) {
    // P. ej. la "Simular notificación" del panel de MP manda un pago inexistente (id 123456).
    logger.warn("Pago de Mercado Pago no encontrado", { dataId, error: String(e) });
    res.status(200).send("pago no encontrado");
    return;
  }
  const orderId = payment.external_reference;
  if (!orderId) {
    res.status(200).send("sin referencia");
    return;
  }
  if (payment.status === "approved") {
    const result = await markOrderPaid(orderId, String(payment.id));
    if (result === "late") {
      await getFirestore().collection("orders").doc(orderId).update({ refund: { status: "pending", amount: payment.transaction_amount } });
      await refundOrder(orderId);
    }
  } else if (["rejected", "cancelled"].includes(payment.status)) {
    await cancelPendingOrder(orderId, "payment_rejected");
  }
  res.status(200).send("ok");
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
