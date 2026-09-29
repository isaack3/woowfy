# Auditoría de código — Woowfy (2026-09-28)

Contexto para quien retome esto: Woowfy es un clon de Too Good To Go para Chile. App Flutter Web + Firebase (proyecto `woowfy-app`), Cloud Functions en TypeScript (`functions/src`), pagos con Mercado Pago Checkout Pro (`PAYMENTS_PROVIDER=mercadopago` en `functions/.env`). UI en español, rutas en inglés.

Se revisó: Cloud Functions, `firestore.rules`, `storage.rules`, `firebase.json`, `firestore.indexes.json`, scripts de `tool/`, app Flutter (`lib/`), `web/` y `landing/`.

- `npx tsc --noEmit` (functions) → sin errores.
- `flutter analyze` → sin problemas.
- No hay código malicioso ni secretos expuestos. `functions/.env` está versionado a propósito: sólo contiene `PAYMENTS_PROVIDER` (no es secreto). Las API keys de `lib/firebase_options.dart` y `web/firebase-messaging-sw.js` son públicas por diseño de Firebase.

**Estado (28-09-2026): corregido y desplegado** #1–#9 y los menores de recordatorios y comentarios; probado en emuladores
y con datos de producción migrados (ver ROADMAP → Sprint 4, etapa A). Aceptados por ahora: subidas a Storage y ventana `ts`.

---

## 🔴 Importantes

### 1. El comercio puede marcar pedidos como retirados sin entregar la bolsa
- **Dónde:** `firestore.rules` (match `/orders/{orderId}`, regla `allow read`) + `functions/src/orders.ts` (`redeemOrder`) + `functions/src/payouts.ts` (`createPayout`).
- **Problema:** la regla deja que el dueño del local lea el pedido completo, incluido `pickupCode`. El comercio puede llamar `redeemOrder` con los códigos de todos sus pedidos pagados sin que el cliente aparezca; quedan `picked_up` y `createPayout` los liquida. El código de retiro no protege contra fraude del comercio.
- **Es una decisión de negocio.** Opciones: guardar `pickupCode` fuera del documento que lee el comercio (p. ej. subcolección `orders/{id}/private/code` legible sólo por el cliente), o guardar sólo un hash en el pedido y que `redeemOrder` compare el hash. Ojo: la app del cliente (`lib/features/orders/order_page.dart`) muestra el QR a partir de `order.pickupCode`, así que habría que ajustar de dónde lo lee.

### 2. El correo del dueño de cada local es público
- **Dónde:** `firestore.rules` (match `/stores/{storeId}`, `allow read: if resource.data.status == 'approved' || ...`) + `lib/data/repository.dart` (`requestStore` escribe `ownerEmail`).
- **Problema:** cualquiera, incluso sin sesión, puede leer los locales aprobados, y el documento trae `ownerEmail` (dato personal). Se pueden juntar los correos de todos los dueños.
- **Arreglo sugerido:** mover `ownerEmail` (y cualquier dato privado) a un documento aparte, p. ej. `stores/{id}/private/contact`, legible sólo por el dueño y el admin. Revisar dónde lo lee el panel admin (`lib/features/admin/stores_tabs.dart`, modelo `Store` en `lib/data/models.dart`).

### 3. Un comercio puede inventarse su calificación al crear el local
- **Dónde:** `firestore.rules`, `match /stores/{storeId}`, regla `allow create`.
- **Problema:** `touchesRating` sólo se revisa al *editar*. Al *crear* se puede mandar `ratingAvg: 5, ratingCount: 500, ratingSum: 2500`. Cuando el admin lo aprueba, `onBagCreated` y `onStoreUpdated` (`functions/src/notifications.ts`, `functions/src/stores.ts`) copian esa nota a las bolsas.
- **Arreglo sugerido:** en `allow create` agregar
  `&& !request.resource.data.keys().hasAny(['ratingSum','ratingCount','ratingAvg','storeRatingAvg','storeRatingCount'])`.
  Sirve evaluar también limitar los campos permitidos con `keys().hasOnly([...])` (evita, p. ej., que el comercio se ponga `lat`/`lng`, `reviewedAt` o `statusReason` al crearlo).

### 4. Al editar una bolsa no se valida el precio
- **Dónde:** `firestore.rules`, `match /bags/{bagId}`, regla `allow update`.
- **Problema:** al crear se exige `price > 0 && price < originalPrice`, pero al editar no: el comercio puede dejar el precio en 0, en negativo o mayor que el original. `createOrder` usa `bag.price` tal cual.
- **Arreglo sugerido:** agregar en `allow update` para el comercio (no para el admin, o también si se quiere):
  `&& request.resource.data.price > 0 && request.resource.data.price < request.resource.data.originalPrice`.
  Opcional: validarlo también en `createOrder` (`functions/src/orders.ts`) como defensa en el servidor.

### 5. `cancelBag` puede quedarse con un pago sin reembolsarlo
- **Dónde:** `functions/src/orders.ts`, función `cancelBag`.
- **Problema A (carrera):** la función consulta los pedidos `pending_payment`/`paid` y después los actualiza uno por uno con `d.ref.update(...)`, sin transacción. Si un pedido pasa de `pending_payment` a `paid` justo entre la consulta y el update (llega el webhook), se cancela con el `wasPaid` viejo (`false`): queda `cancelled`, sin `refund`, con el dinero cobrado. Además `markOrderPaid` ya no lo detecta como "late" porque ya tiene `payment.paymentId`.
- **Problema B:** si `pushToUser` lanza un error, se corta el `for` y los pedidos siguientes quedan sin cancelar ni reembolsar.
- **Arreglo sugerido:** cancelar cada pedido dentro de una transacción que relea el estado (`fresh.status`) y decida el reembolso según ese estado fresco; después llamar `refundOrder`. Envolver `pushToUser` en `try/catch` con `logger.warn`.

---

## 🟡 Medios

### 6. No hay límite de reservas por usuario
- **Dónde:** `functions/src/orders.ts`, `createOrder`.
- **Problema:** una cuenta puede reservar todas las unidades de todas las bolsas (cada reserva dura 15 min, `PAYMENT_TIMEOUT_MINUTES`) y repetirlo indefinidamente. Además cada reserva crea una preferencia en Mercado Pago.
- **Arreglo sugerido:** antes de reservar, contar los pedidos `pending_payment` del usuario (p. ej. máx. 2) y rechazar con `resource-exhausted`. Posible índice `orders (userUid, status)`.

### 7. El webhook no compara el monto pagado con el del pedido
- **Dónde:** `functions/src/orders.ts`, `mercadoPagoWebhook` → `applyApprovedPayment`.
- **Problema:** `reconcileOrder` (cambio nuevo, aún sin commitear) sí rechaza pagos con `transaction_amount < order.amount`, pero el webhook no. El criterio no es el mismo en las dos rutas.
- **Arreglo sugerido:** mover la comprobación de monto a `applyApprovedPayment` (leyendo el pedido) para que ambas rutas la compartan.

### 8. `createPayout` no usa transacción
- **Dónde:** `functions/src/payouts.ts`.
- **Problema:** lee los pedidos sin `payoutId`, crea el payout y después marca los pedidos en lotes. Un doble clic o dos admins al mismo tiempo pueden registrar dos liquidaciones con los mismos pedidos.
- **Arreglo sugerido:** un candado simple (p. ej. doc `stores/{id}/private/payoutLock` dentro de una transacción) o marcar los pedidos dentro de una transacción que verifique `!payoutId` (máx. 500 escrituras por transacción). Revisar también que el botón en `lib/features/admin/sales_tab.dart` quede deshabilitado mientras corre.

### 9. `createOrder` no revisa si el local sigue aprobado
- **Dónde:** `functions/src/orders.ts`, `createOrder`.
- **Problema:** sólo exige que la bolsa esté `active`. Al suspender un local, las bolsas se pausan desde el cliente del admin (`setStoreStatus` en `lib/data/repository.dart`), sin garantía del servidor. Si ese batch falla o se crea una bolsa recurrente después, se podría comprar.
- **Arreglo sugerido:** dentro de la transacción, leer `stores/{bag.storeId}` y exigir `status == 'approved'`.

---

## ⚪ Menores

- **`sendPickupReminders`** (`functions/src/notifications.ts`): la consulta `status == 'paid' && pickupStart <= ahora+45min` no tiene límite inferior de fecha, así que en cada corrida (cada 15 min) revisa todos los pedidos pagados que nunca se retiraron. Agregar `pickupStart >= ahora - X horas`.
- **Comentarios desactualizados:** `functions/.env` dice "mercadopago (pendiente)" y el comentario de `functions/src/payments.ts` dice que mock es el proveedor por defecto, pero hoy está en `mercadopago`.
- **Storage** (`storage.rules`): cualquier usuario con sesión puede subir imágenes públicas de hasta 5 MB a `uploads/{uid}/`, aunque no sea comercio. Riesgo de abuso como hosting gratis. Aceptable por ahora; se podría limitar con Firestore o una custom claim.
- **Webhook de Mercado Pago** (`validMercadoPagoSignature` en `payments.ts`): no revisa la antigüedad de `ts` (ventana contra repetición). Bajo impacto, porque luego se consulta el pago real a la API.

---

## Cambios sin commitear al momento de la auditoría

Archivos: `functions/src/index.ts`, `functions/src/orders.ts`, `functions/src/payments.ts`, `lib/data/repository.dart`, `lib/features/orders/order_page.dart`.

Agregan una conciliación con Mercado Pago como respaldo del webhook:
- `syncOrderPayment` (callable), que el cliente llama al abrir un pedido pendiente o al tocar "Ya pagué, verificar".
- `reconcileOrder` + `MercadoPagoProvider.findApprovedPayment` (búsqueda por `external_reference`).
- `expirePendingOrders` concilia antes de vencer la reserva.

Revisados: están bien planteados (no confían en datos del cliente y son idempotentes). **No arreglan** el problema de fondo: el webhook sigue rechazando las notificaciones por "firma inválida", y hay que regenerar la clave en el panel de MP y actualizar el secreto `MP_WEBHOOK_SECRET`. No relajar la verificación de firma.

## Orden sugerido para corregir

1. #5 (`cancelBag`) y #4 (precio al editar bolsa): dinero y reglas, cambios chicos.
2. #3 (calificación al crear local) y #2 (correo público).
3. #7, #9, #6, #8.
4. #1: requiere decisión de negocio con el usuario.

Después de cambiar reglas o funciones: `npx tsc --noEmit` en `functions/`, `flutter analyze`, probar con emuladores (`npm --prefix functions run seed`) y desplegar (`firebase deploy --only firestore:rules,functions`).
