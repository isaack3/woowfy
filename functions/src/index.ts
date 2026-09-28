import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
// Santiago: misma región que Firestore para menor latencia.
setGlobalOptions({ region: "southamerica-west1", maxInstances: 10 });

export { confirmMockPayment, createOrder, expirePendingOrders, redeemOrder } from "./orders.js";
