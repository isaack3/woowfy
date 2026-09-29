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
/** Arrepentimiento: el cliente también puede cancelar (con reembolso) hasta estos minutos después de pagar. */
export const CANCEL_GRACE_MINUTES = 15;
/** Reservas sin pagar que puede tener una persona al mismo tiempo. */
const MAX_PENDING_ORDERS = 2;

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

  // Evita que una cuenta acapare bolsas con reservas que no paga.
  const unpaid = await db.collection("orders")
    .where("userUid", "==", uid).where("status", "==", "pending_payment").limit(MAX_PENDING_ORDERS).get();
  if (unpaid.size >= MAX_PENDING_ORDERS) {
    throw new HttpsError("resource-exhausted",
      `Tienes ${MAX_PENDING_ORDERS} reservas sin pagar. Págalas o cancélalas antes de reservar otra.`);
  }

  const order = await db.runTransaction(async (tx) => {
    const snap = await tx.get(bagRef);
    const bag = snap.data();
    const now = Timestamp.now();
    if (!bag || !bag.active || bag.quantityAvailable < 1 || bag.pickupEnd.toMillis() <= now.toMillis()) {
      throw new HttpsError("failed-precondition", "Esta bolsa ya no está disponible.");
    }
    const store = (await tx.get(db.collection("stores").doc(bag.storeId))).data();
    if (store?.status !== "approved") throw new HttpsError("failed-precondition", "Este local no está disponible.");
    if (!(bag.price > 0 && bag.price < bag.originalPrice)) {
      throw new HttpsError("failed-precondition", "Esta bolsa tiene un precio no válido.");
    }
    // El código de retiro es único por local mientras el pedido esté vigente. Se guarda aparte del pedido para
    // que el comercio no lo pueda leer: solo lo ve el cliente, y el comercio lo valida cuando se lo muestran.
    let code = "";
    let codeRef = db.collection("pickupCodes").doc();
    for (let i = 0; i < 5 && !code; i++) {
      const candidate = pickupCode();
      const ref = db.collection("pickupCodes").doc(`${bag.storeId}_${candidate}`);
      const taken = (await tx.get(ref)).data();
      if (!taken || taken.pickupEnd.toMillis() + REDEEM_GRACE_MINUTES * 60_000 < now.toMillis()) {
        code = candidate;
        codeRef = ref;
      }
    }
    if (!code) throw new HttpsError("unavailable", "No pudimos reservar. Intenta de nuevo.");
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
      status: "pending_payment",
      expiresAt: Timestamp.fromMillis(now.toMillis() + PAYMENT_TIMEOUT_MINUTES * 60_000),
      createdAt: FieldValue.serverTimestamp(),
    };
    tx.update(bagRef, { quantityAvailable: FieldValue.increment(-1) });
    tx.set(orderRef, data);
    tx.set(orderRef.collection("private").doc("pickup"), { code, userUid: uid });
    tx.set(codeRef, { orderId: orderRef.id, storeId: bag.storeId, pickupEnd: bag.pickupEnd });
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

/** Marca el pedido como pagado; si la reserva ya había vencido, reembolsa el pago. */
async function applyApprovedPayment(orderId: string, paymentId: string, amount: number): Promise<"paid" | "late" | "noop"> {
  // Misma verificación para el webhook y la conciliación: el pago debe cubrir el monto del pedido.
  const order = (await getFirestore().collection("orders").doc(orderId).get()).data();
  if (!order || Number(amount) < Number(order.amount)) {
    logger.error("Pago aprobado que no calza con el pedido", { orderId, paymentId, amount });
    return "noop";
  }
  const result = await markOrderPaid(orderId, paymentId);
  if (result === "late") {
    await getFirestore().collection("orders").doc(orderId).update({ refund: { status: "pending", amount } });
    await refundOrder(orderId);
  }
  return result;
}

/**
 * Red de seguridad por si el aviso del webhook no llega: el servidor le pregunta a Mercado Pago, con nuestro
 * token, si el pedido tiene un pago aprobado. No usa ningún dato enviado por el cliente.
 */
async function reconcileOrder(orderId: string): Promise<"paid" | "late" | "noop" | "none"> {
  if (paymentProvider().name !== "mercadopago") return "none";
  const payment = await mercadoPago().findApprovedPayment(orderId);
  if (!payment || payment.external_reference !== orderId) return "none";
  const result = await applyApprovedPayment(orderId, String(payment.id), payment.transaction_amount);
  if (result !== "noop") logger.info("Pedido conciliado con Mercado Pago", { orderId, paymentId: payment.id, result });
  return result;
}

/** El cliente vuelve de pagar (o toca "Ya pagué"): verificamos el pago sin esperar al webhook. */
export const syncOrderPayment = onCall({ secrets: PAYMENT_SECRETS }, async (req) => {
  const uid = requireUid(req.auth?.uid);
  const orderId = String(req.data?.orderId ?? "");
  const order = orderId ? (await getFirestore().collection("orders").doc(orderId).get()).data() : undefined;
  if (!order || order.userUid !== uid) throw new HttpsError("not-found", "Pedido no encontrado.");
  if (order.status !== "pending_payment") return { status: order.status };
  const result = await reconcileOrder(orderId);
  return { status: result === "paid" ? "paid" : "pending_payment" };
});

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
  const grace = order.paidAt ? order.paidAt.toMillis() + CANCEL_GRACE_MINUTES * 60_000 : 0;
  if (Date.now() > Math.max(limit, grace)) {
    throw new HttpsError("failed-precondition",
      `Solo puedes cancelar hasta ${CANCEL_HOURS_BEFORE} horas antes del inicio del retiro ` +
      `o dentro de ${CANCEL_GRACE_MINUTES} minutos después de pagar.`);
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
    // Se relee el estado dentro de una transacción: si el pago se confirmó recién, se cancela como pagado y se
    // reembolsa (si no, quedaría cancelado con el dinero cobrado). Un pago que llegue después lo reembolsa
    // markOrderPaid como "late".
    const o = await db.runTransaction(async (tx) => {
      const fresh = (await tx.get(d.ref)).data();
      if (!fresh || !["pending_payment", "paid"].includes(fresh.status)) return null;
      const wasPaid = fresh.status === "paid";
      tx.update(d.ref, {
        status: "cancelled", cancelReason: "store", storeMessage: reason, cancelledAt: FieldValue.serverTimestamp(),
        ...(wasPaid ? { refund: { status: "pending", amount: fresh.amount } } : {}),
      });
      return { wasPaid, userUid: fresh.userUid as string, storeName: fresh.storeName as string, amount: fresh.amount as number };
    });
    if (!o?.wasPaid) continue;
    await refundOrder(d.id);
    refunded++;
    try {
      await pushToUser(o.userUid, `${o.storeName} canceló tu bolsa`,
        `${reason} Te devolvimos $${Number(o.amount).toLocaleString("es-CL")}.`, `/order/${d.id}`);
    } catch (e) {
      logger.warn("No se pudo avisar la cancelación", { orderId: d.id, error: String(e) });
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
    await applyApprovedPayment(orderId, String(payment.id), payment.transaction_amount);
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

  // El código vive en pickupCodes/{storeId}_{código}, que solo lee el servidor.
  const lookup = (await db.collection("pickupCodes").doc(`${storeId}_${code}`).get()).data();
  const doc = lookup ? await db.collection("orders").doc(lookup.orderId).get() : null;
  const now = Date.now();
  if (!doc?.exists || doc.data()?.storeId !== storeId || doc.data()?.status !== "paid") {
    const redeemed = doc?.data()?.status === "picked_up";
    throw new HttpsError("not-found", redeemed ? "Este pedido ya fue retirado." : "Código no válido.");
  }
  const order = doc.data()!;
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
 * Pedidos pagados que no se retiraron a tiempo: pasan a "no_show". No hay reembolso (la comida se apartó para el
 * cliente, ver /terms) y se le pagan igual al local en la próxima liquidación.
 */
export const markNoShows = onSchedule({
  schedule: "every 30 minutes",
  region: "southamerica-east1", // Cloud Scheduler no existe en Santiago
  timeZone: "America/Santiago",
}, async () => {
  const db = getFirestore();
  // Mismo margen que redeemOrder: pasado este punto ya no se puede validar el retiro.
  const cutoff = Timestamp.fromMillis(Date.now() - REDEEM_GRACE_MINUTES * 60_000);
  const late = await db.collection("orders")
    .where("status", "==", "paid").where("pickupEnd", "<", cutoff).limit(450).get();
  if (late.empty) return;
  const batch = db.batch();
  late.docs.forEach((d) => batch.update(d.ref, { status: "no_show", noShowAt: FieldValue.serverTimestamp() }));
  await batch.commit();
  logger.info("Pedidos no retirados", { count: late.size });
});

/**
 * Libera reservas cuyo pago no se completó a tiempo.
 * Corre en São Paulo porque Cloud Scheduler no está disponible en southamerica-west1 (Santiago).
 */
export const expirePendingOrders = onSchedule({
  schedule: "every 5 minutes",
  region: "southamerica-east1",
  timeZone: "America/Santiago",
  secrets: PAYMENT_SECRETS,
}, async () => {
  const expired = await getFirestore().collection("orders")
    .where("status", "==", "pending_payment")
    .where("expiresAt", "<", Timestamp.now())
    .limit(200)
    .get();
  await Promise.all(expired.docs.map(async (d) => {
    // Antes de liberar la bolsa, confirmamos que no haya un pago aprobado cuyo aviso se perdió.
    try {
      if ((await reconcileOrder(d.id)) === "paid") return;
    } catch (e) {
      logger.warn("No se pudo consultar el pago antes de vencer la reserva", { orderId: d.id, error: String(e) });
    }
    await cancelPendingOrder(d.id, "payment_timeout");
  }));
});
