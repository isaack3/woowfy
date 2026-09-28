import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";

/**
 * Bolsas recurrentes: el comercio define una plantilla (bagTemplates/{id}) con días de la semana y
 * horario de retiro, y cada día se publica la bolsa de ese día automáticamente.
 * El id de la bolsa diaria es `${templateId}_${yyyymmdd}`, así nunca se duplica.
 */
const TZ = "America/Santiago";

/** Fecha de hoy en Chile: { ymd: "2026-09-28", weekday: 1..7 (lunes=1) }. */
function todayInChile(now = new Date()) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit", weekday: "short" })
      .formatToParts(now).map((p) => [p.type, p.value]),
  );
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(parts.weekday) + 1;
  return { ymd: `${parts.year}-${parts.month}-${parts.day}`, weekday };
}

/** Convierte "2026-09-28" + "19:30" (hora de Chile) a un instante exacto, respetando horario de verano. */
function chileTime(ymd: string, hhmm: string): Date {
  const guess = new Date(`${ymd}T${hhmm}:00Z`);
  const offset = new Intl.DateTimeFormat("en-US", { timeZone: TZ, timeZoneName: "longOffset" })
    .formatToParts(guess).find((p) => p.type === "timeZoneName")?.value ?? "GMT-03:00";
  const iso = offset === "GMT" ? "+00:00" : offset.replace("GMT", "");
  return new Date(`${ymd}T${hhmm}:00${iso}`);
}

interface Template {
  storeId: string;
  title: string;
  description?: string;
  originalPrice: number;
  price: number;
  quantity: number;
  pickupStart: string; // "HH:mm"
  pickupEnd: string;
  days: number[]; // 1 (lunes) .. 7 (domingo)
  active: boolean;
  imageUrl?: string | null;
}

/** Crea la bolsa de hoy para la plantilla si corresponde y aún no existe. Devuelve true si la creó. */
async function ensureTodayBag(templateId: string, t: Template, now = new Date()): Promise<boolean> {
  const { ymd, weekday } = todayInChile(now);
  if (!t.active || !t.days?.includes(weekday)) return false;
  const pickupStart = chileTime(ymd, t.pickupStart);
  const pickupEnd = chileTime(ymd, t.pickupEnd);
  if (pickupEnd <= now) return false;

  const db = getFirestore();
  const store = (await db.doc(`stores/${t.storeId}`).get()).data();
  if (!store || store.status !== "approved") return false;

  const ref = db.doc(`bags/${templateId}_${ymd.replaceAll("-", "")}`);
  try {
    await ref.create({
      storeId: t.storeId,
      storeName: store.name,
      storeLogoUrl: store.logoUrl ?? null,
      category: store.category ?? null,
      comuna: store.comuna,
      region: store.region ?? "",
      lat: store.lat ?? null,
      lng: store.lng ?? null,
      address: store.address,
      title: t.title,
      description: t.description ?? "",
      originalPrice: t.originalPrice,
      price: t.price,
      quantityAvailable: t.quantity,
      pickupStart: Timestamp.fromDate(pickupStart),
      pickupEnd: Timestamp.fromDate(pickupEnd),
      active: true,
      imageUrl: t.imageUrl ?? null,
      templateId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  } catch (e) {
    if ((e as { code?: number }).code === 6) return false; // ya existía (ALREADY_EXISTS)
    throw e;
  }
}

/** Al crear o reactivar una plantilla, publica la bolsa de hoy si todavía está a tiempo. */
export const onBagTemplateWritten = onDocumentWritten("bagTemplates/{id}", async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;
  await ensureTodayBag(after.id, after.data() as Template);
});

/** Cada madrugada publica las bolsas recurrentes del día. */
export const publishRecurringBags = onSchedule({
  schedule: "every day 05:00",
  timeZone: TZ,
  region: "southamerica-east1", // Cloud Scheduler no existe en Santiago
}, async () => {
  const templates = await getFirestore().collection("bagTemplates").where("active", "==", true).get();
  let created = 0;
  for (const d of templates.docs) {
    if (await ensureTodayBag(d.id, d.data() as Template)) created++;
  }
  logger.info(`Bolsas recurrentes publicadas: ${created} de ${templates.size} plantillas activas`);
});

export const _test = { todayInChile, chileTime };
