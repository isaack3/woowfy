import { createHash } from "node:crypto";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { cancelPendingOrder } from "./orders.js";

/**
 * Cuenta → "Eliminar mi cuenta" (derecho de supresión, Ley 21.719). Borra el perfil, los favoritos, los avisos, la
 * inscripción en la lista de espera, las fotos subidas y la cuenta de acceso. Las compras se conservan por obligación
 * tributaria, pero quedan solo con un identificador que ya no corresponde a ninguna cuenta; las calificaciones siguen
 * públicas como "Cliente". No se puede si la persona tiene un local o un pedido pagado por retirar.
 */
export const deleteAccount = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  const db = getFirestore();

  const user = (await db.doc(`users/${uid}`).get()).data();
  if (user?.role === "admin") {
    throw new HttpsError("failed-precondition", "Una cuenta de administrador no se elimina desde la app.");
  }
  const stores = await db.collection("stores").where("ownerUid", "==", uid).limit(1).get();
  if (!stores.empty) {
    throw new HttpsError("failed-precondition",
      "Tu cuenta tiene un local asociado. Escríbenos a hola@passva.com para darlo de baja y eliminar tus datos.");
  }
  const paid = await db.collection("orders").where("userUid", "==", uid).where("status", "==", "paid").limit(1).get();
  if (!paid.empty) {
    throw new HttpsError("failed-precondition",
      "Tienes un pedido pagado por retirar. Retíralo o cancélalo antes de eliminar tu cuenta.");
  }

  // Reservas sin pagar: se liberan para que otra persona pueda comprar la bolsa.
  const pending = await db.collection("orders").where("userUid", "==", uid).where("status", "==", "pending_payment").get();
  for (const d of pending.docs) await cancelPendingOrder(d.id, "account_deleted");

  // Calificaciones: siguen visibles para el local, pero sin nombre ni cuenta.
  const reviews = await db.collection("reviews").where("userUid", "==", uid).get();
  for (let i = 0; i < reviews.size; i += 450) {
    const batch = db.batch();
    reviews.docs.slice(i, i + 450).forEach((d) => batch.update(d.ref, { userName: "Cliente", userUid: FieldValue.delete() }));
    await batch.commit();
  }

  // Perfil con sus favoritos (subcolección) y tokens de notificaciones.
  await db.recursiveDelete(db.doc(`users/${uid}`));

  // Inscripción en la lista de espera con el mismo correo (mismo id que usa joinWaitlist).
  const email = req.auth?.token.email?.trim().toLowerCase();
  if (email) await db.doc(`waitlist/${createHash("sha256").update(email).digest("hex").slice(0, 40)}`).delete();

  try {
    await getStorage().bucket().deleteFiles({ prefix: `uploads/${uid}/` });
  } catch (e) {
    logger.warn("No se pudieron borrar los archivos de la cuenta", { uid, error: String(e) });
  }

  await getAuth().deleteUser(uid);
  logger.info("Cuenta eliminada a pedido de la persona", { uid, pendingCancelled: pending.size, reviews: reviews.size });
  return { ok: true };
});
