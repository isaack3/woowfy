import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

initializeApp();
// Santiago: misma región que Firestore para menor latencia.
setGlobalOptions({ region: "southamerica-west1", maxInstances: 10 });

export {
  cancelBag, cancelOrder, confirmMockPayment, createOrder, expirePendingOrders, markNoShows, mercadoPagoWebhook, redeemOrder, syncOrderPayment,
} from "./orders.js";
export { rateOrder } from "./reviews.js";
export { createAllPayouts, createPayout } from "./payouts.js";
export { trackEvent } from "./analytics.js";
export { joinWaitlist } from "./waitlist.js";
export { onWaitlistCreated, sendTestEmail } from "./email.js";
export { onBagTemplateWritten, publishRecurringBags } from "./recurring.js";
export { onStoreCreated, onStoreUpdated } from "./stores.js";
export { onBagCreated, sendPickupReminders } from "./notifications.js";
