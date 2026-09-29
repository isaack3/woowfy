# Woowfy

Marketplace de **bolsas sorpresa** contra el desperdicio de comida: los locales publican lo que no
vendieron en el día, los clientes lo reservan y pagan en línea, y lo retiran con un código QR.
Chile primero, luego Latam.

- **Landing:** https://woowfy.com (modo "en construcción" con lista de espera)
- **App:** https://app.woowfy.com
- **Hoja de ruta y estado:** [ROADMAP.md](ROADMAP.md)

## Stack

| Parte | Tecnología |
|---|---|
| App (web hoy; Android/iOS después) | Flutter · go_router · Material 3 · flutter_map (OpenStreetMap) |
| Landing | HTML + CSS estático (`landing/`), pensado para SEO, con lista de espera y páginas legales |
| Backend | Firebase: Auth (correo + Google), Firestore, Storage (fotos), Cloud Functions (TypeScript, Node 22), Cloud Messaging (push), Hosting |
| Pagos | Proveedor intercambiable: `mock` hoy, Mercado Pago después |
| Correos | Resend (pendiente de activar) |
| Builds móviles | Codemagic (`codemagic.yaml`), para compilar iOS sin Mac |

Proyecto Firebase: **`woowfy-app`** (plan Blaze). Paquete Android / Bundle iOS: `com.woowfy.woowfy`.

## Estructura

```
lib/
  main.dart, app.dart
  core/          tema y logo, router, formato CLP, backend (emuladores/región), checkout,
                 ubicación, push (FCM), instalación PWA, enlaces legales
  data/          modelos, repositorio Firestore/Functions/Storage, regiones de Chile
  features/
    shell/       navegación principal (Bolsas / Mis pedidos / Cuenta) y encabezado verde
    home/        bolsas del día: filtros, orden, mapa y distancia
    bags/        tarjeta, detalle (favorito, compartir) y "Reservar y pagar"
    auth/        ingreso / registro (correo y Google), recuperar contraseña
    orders/      checkout simulado, comprobante con QR, "Mis pedidos"
    account/     cuenta: nombre, tu impacto, notificaciones, instalar app, legales
    merchant/    panel del comercio: perfil, bolsas (y recurrentes), cancelar bolsa, validar retiro con QR,
                 ventas y pagos
    admin/       solicitudes, comercios, ventas, interesados, usuarios, correo
assets/brand/    isotipo usado en la app
functions/src/
  orders.ts          createOrder, confirmMockPayment, redeemOrder, expirePendingOrders,
                     cancelOrder (cliente), cancelBag (comercio), mercadoPagoWebhook
  payments.ts        PaymentProvider: mock | mercadopago (Checkout Pro, reembolsos, firma del webhook)
  reviews.ts         rateOrder: calificación de pedidos retirados y nota del local
  payouts.ts         createPayout: liquidación de ventas al comercio (admin)
  waitlist.ts        joinWaitlist (formulario "Avísame" de la landing)
  email.ts           onWaitlistCreated (bienvenida vía Resend) y sendTestEmail
  recurring.ts       bolsas recurrentes: onBagTemplateWritten + publishRecurringBags (05:00 Chile)
  stores.ts          onStoreCreated/onStoreUpdated: coordenadas y copia del perfil a sus bolsas
  geo.ts             geocodificación de direcciones (Nominatim / OpenStreetMap)
  notifications.ts   push: aviso a seguidores (onBagCreated) y recordatorio de retiro (cada 15 min)
  chile.ts           regiones de Chile (validación)
functions/scripts/seed-emulators.mjs   datos y cuentas de prueba para los emuladores
landing/         woowfy.com: index.html, terms.html, privacy.html, íconos, og-image, manifest
brand/           brand kit v2 original + brand/fixed/ (íconos corregidos)
tool/
  stamp-web-build.mjs        agrega ?v=<hash> a main.dart.js en cada deploy (evita caché vieja)
  set-storage-cors.mjs       aplica storage-cors.json al bucket (necesario para ver fotos en la app)
  backfill-store-coords.mjs  calcula coordenadas de locales que no las tienen
firestore.rules, firestore.indexes.json, storage.rules, storage-cors.json
```

## Perfiles

| Perfil | Cómo se obtiene | Qué hace |
|---|---|---|
| Cliente | Registrándose | Ve bolsas (lista o mapa), sigue locales, reserva y paga, retira con QR |
| Comercio | Un usuario pide sumar su local y un admin lo aprueba | Perfil del local, publica bolsas (o recurrentes), valida retiros |
| Admin | `role: admin` en `users/{uid}` | Aprueba comercios, ve ventas e inscritos, gestiona usuarios y correo |

El primer admin se asignó a mano; los siguientes se dan desde **Admin → Usuarios**.

## Modelo de datos (Firestore)

| Colección | Contenido | Quién escribe |
|---|---|---|
| `users/{uid}` | email, nombre, `role` (`customer` \| `admin`), `fcmTokens` (push) | el usuario (sin cambiar su rol); admin |
| `users/{uid}/favorites/{storeId}` | locales que sigue el usuario | el propio usuario |
| `stores/{id}` | local: categoría, logo, descripción, horario, dirección, `lat/lng`; `status`: `pending` → `approved` / `rejected` / `suspended` | el dueño crea y edita su perfil; admin cambia el estado |
| `bags/{id}` | bolsa del día: precio, stock, horario, foto, categoría, logo y coordenadas del local | comercio aprobado (o la función de recurrentes); admin puede pausar |
| `bagTemplates/{id}` | bolsa recurrente: días de la semana, horario `HH:mm`, precio, cantidad | comercio aprobado |
| `orders/{id}` | compra: estado, monto, precio original, comisión, código de retiro, cancelación y reembolso, calificación, liquidación | **solo Cloud Functions** |
| `reviews/{orderId}` | calificación (1–5) y comentario de un pedido retirado | **solo la función** `rateOrder`; lectura pública |
| `payouts/{id}` | pago de Woowfy a un comercio: pedidos, ventas, comisión, monto y nota | **solo la función** `createPayout`; lo ve el admin y el comercio |
| `waitlist/{hash}` | inscritos de la landing: nombre, correo, tipo, región, comuna, estado del correo | **solo funciones**; lee el admin |
| `config/email` | remitente de los correos | solo admin (Admin → Correo) |

Estados de un pedido: `pending_payment` (bolsa reservada 15 min) → `paid` (muestra QR) →
`picked_up` (el comercio validó el código). `cancelled` si no se paga a tiempo, se rechaza el pago, el cliente
cancela (hasta 2 h antes del retiro, con reembolso) o el comercio cancela la bolsa (reembolso y aviso).
La nota de un local solo la escribe el servidor: las reglas impiden que el comercio la modifique.

## Rutas de la app

Las rutas van en inglés; los textos de la interfaz, en español de Chile.

| Ruta | Pantalla |
|---|---|
| `/` | Bolsas disponibles (todo Chile) — con barra de navegación |
| `/orders` | Mis pedidos — con barra de navegación |
| `/account` | Cuenta — con barra de navegación |
| `/bag/:id` | Detalle de una bolsa |
| `/login?from=…` | Ingreso / registro |
| `/order/:id` | Comprobante con QR |
| `/mock-checkout/:id` | Pago simulado |
| `/merchant` | Panel del comercio |
| `/merchant/sales` | Ventas y pagos del comercio |
| `/admin` | Panel admin |

Landing: `/`, `/terms`, `/privacy`, y `/api/waitlist` (rewrite hacia la función `joinWaitlist`).

## Desarrollo local (emuladores)

Los emuladores no tocan la base real.

```bash
firebase emulators:start --only auth,firestore,functions
```

```bash
npm --prefix functions run seed
```

```bash
flutter run -d chrome --dart-define=USE_EMULATORS=true
```

- Cuentas de prueba (cliente, comercio aprobado, comercio pendiente y admin): ver
  `functions/scripts/seed-emulators.mjs`.
- Emulator UI: http://127.0.0.1:4000 · Los datos se borran al cerrar: vuelve a correr el `seed`.
- Las tareas programadas (vencer reservas, recurrentes, recordatorios) no se ejecutan en el emulador.
- El emulador de **Storage** falla con Java 25 (advertencia de `sun.misc.Unsafe`): sin él, el seed deja la
  bolsa de ejemplo sin foto. Las reglas de Storage se prueban con la Rules API (`projects.test`).
- Para las funciones con secretos, crea `functions/.secret.local` (ignorado por git) con valores de prueba:
  `RESEND_API_KEY=...`, `MP_ACCESS_TOKEN=TEST-...`, `MP_WEBHOOK_SECRET=...`.
- Si al iniciar dice que los puertos 4000/8080/9099 están ocupados, quedó un emulador anterior abierto.

Calidad:

```bash
flutter analyze
```

```bash
flutter test
```

```bash
npm --prefix functions run build
```

## Deploy

| Qué | Comando |
|---|---|
| Reglas e índices | `firebase deploy --only firestore` |
| Reglas de Storage | `firebase deploy --only storage` |
| Cloud Functions | `firebase deploy --only functions` |
| Landing | `firebase deploy --only hosting:landing` |
| App | `flutter build web --release` y luego `firebase deploy --only hosting:app` |

- Hosting guarda solo las **últimas 5 versiones** de cada sitio y las imágenes de las functions se borran a
  1 día, para no acumular deploys viejos.
- Nunca despliegues `build/web-emulators`: es un build que apunta a los emuladores.
- Si el build web se comporta distinto al de desarrollo (p. ej. un plugin "no disponible"), corre
  `flutter clean && flutter pub get`: el caché de Flutter puede quedar con un registro de plugins viejo.
- Revisa el build optimizado antes de publicar: algunos errores (como pasar funciones JS externas como valor)
  no los detecta `flutter analyze`, solo `flutter build web`.

Regiones: Firestore, Storage y las funciones en **Santiago** (`southamerica-west1`). Las tareas programadas
(`expirePendingOrders`, `publishRecurringBags`, `sendPickupReminders`) en **São Paulo**
(`southamerica-east1`), porque Cloud Scheduler no existe en Santiago.

## Dominios

DNS administrado en **Piensa Solutions**.

| Dominio | Registro DNS | Sitio de Firebase Hosting |
|---|---|---|
| `woowfy.com` | A `199.36.158.100` + TXT `hosting-site=woowfy-app` | `woowfy-app` (landing) |
| `www.woowfy.com` | CNAME `woowfy-app.web.app` | `woowfy-app` (landing) |
| `app.woowfy.com` | CNAME `woowfy-app-web.web.app` | `woowfy-app-web` (app) |

Un nombre con CNAME no puede tener otros registros, y el dominio raíz (`@`) no admite CNAME.
El TXT `google-site-verification` es de Google Search Console: no borrarlo.

## Funcionalidades clave

- **Lista de espera (landing):** el formulario "Avísame cuando lancen" envía a `/api/waitlist`, sin cargar
  Firebase en la página. Los inscritos se ven en **Admin → Interesados** (copiar correos o CSV).
- **Bolsas recurrentes:** el comercio activa "Repetir" y elige días; se publican solas a las 5:00 (hora de
  Chile, con horario de verano) o apenas se crean si aún es hora. El id diario evita duplicados.
- **Mapa y cercanía:** OpenStreetMap vía `flutter_map` (sin clave). Las coordenadas del local se calculan al
  crearlo o cambiar su dirección; para locales antiguos: `node tool/backfill-store-coords.mjs`. La ubicación
  del cliente la pide el navegador y solo se usa en el dispositivo.
- **Notificaciones push:** Firebase Cloud Messaging + `web/firebase-messaging-sw.js`. Necesitan la clave
  pública VAPID en `lib/core/push.dart` (`webPushVapidKey`); mientras esté vacía, la app muestra "Muy pronto".
- **Instalar la app (PWA):** `web/index.html` captura el evento del navegador y la pantalla Cuenta ofrece instalar.
- **Fotos (Storage):** se suben a `uploads/{uid}/...` (cada usuario solo escribe en su carpeta, imágenes de
  hasta 5 MB). Así las reglas no dependen de Firestore. Para que la app web pueda mostrarlas, el bucket
  necesita CORS (`storage-cors.json`, se aplica con `node tool/set-storage-cors.mjs`).

## Correos (Resend)

- Al inscribirse en la lista de espera, `onWaitlistCreated` envía una bienvenida personalizada con el nombre.
- El remitente se configura en **Admin → Correo**: activar/desactivar, nombre, correo del remitente
  (`@woowfy.com`, dominio verificado en Resend) y "responder a" (p. ej. tu Gmail). **Enviar prueba a mi
  correo** manda la bienvenida al admin conectado.
- La API key va en Secret Manager: `firebase functions:secrets:set RESEND_API_KEY` y luego
  `firebase deploy --only functions:onWaitlistCreated,functions:sendTestEmail`. Hoy tiene un valor provisional.
- Correo entrante: `hola@woowfy.com` se reenviará a Gmail con ImprovMX (pendiente de configurar los MX).
- "Recuperar contraseña" lo envía Firebase Auth (en español), no Resend.

## Páginas legales

`landing/terms.html` (`/terms`) y `landing/privacy.html` (`/privacy`): **borradores** pendientes de revisión
legal y de completar los datos de la SpA (marcados en amarillo). Enlazados desde la landing, el formulario
de lista de espera, el registro, el alta de comercios y la pantalla Cuenta.

## Diseño y marca

- **App:** propuesta A "Verde profundo" (`lib/core/theme.dart`): encabezados verde `#063B25`, fondo crema,
  tarjetas blancas, botones y descuentos en lima. Colores fijos de la marca, español de Chile (hora 24 h).
  Las bolsas muestran su foto o un ícono de "sin imagen"; los locales, su logo o un ícono de tienda.
- **Marca:** brand kit v2 en `brand/`. Paleta: verde `#063B25`, lima `#9BE52C`, coral `#FF694D`, naranja
  `#FF9B4A`, crema `#FFF7E3`, negro `#101713`. Tipografía: **Lato**.
- El isotipo del kit venía descentrado y cortado por la derecha: en `brand/fixed/` están las versiones
  corregidas (las que usan landing, app y `assets/brand/`).

## Pagos (Mercado Pago)

`functions/.env` → `PAYMENTS_PROVIDER=mock` (hoy): checkout simulado, no mueve dinero.
Con `PAYMENTS_PROVIDER=mercadopago` se usa **Checkout Pro**:

1. En [Mercado Pago Developers](https://www.mercadopago.cl/developers) → *Tus integraciones* → crear aplicación
   (Checkout Pro). Para probar, usa las **credenciales de prueba** (el Access Token empieza con `TEST-`) y
   **usuarios de prueba** para pagar; no se mueve dinero real.
2. En la aplicación → *Webhooks* → URL `https://southamerica-west1-woowfy-app.cloudfunctions.net/mercadoPagoWebhook`,
   evento **Pagos**. Copia la **clave secreta** que muestra.
3. Guarda ambos en Secret Manager (hoy tienen un valor provisional):
   `firebase functions:secrets:set MP_ACCESS_TOKEN` y `firebase functions:secrets:set MP_WEBHOOK_SECRET`.
4. Cambia `PAYMENTS_PROVIDER=mercadopago` en `functions/.env` y despliega: `firebase deploy --only functions`.

El webhook verifica la firma (`x-signature`) y consulta el pago a la API antes de marcar el pedido como pagado.
Si un pago llega después de vencida la reserva, se reembolsa solo. Las cancelaciones con pago devuelven el
dinero con la API de reembolsos. Para cobrar de verdad se usan las credenciales de producción de la cuenta de
la SpA. Los tokens van en Secret Manager, **nunca** en archivos del repositorio.

## Móviles (más adelante)

- **Android:** se compila desde Windows (`flutter build appbundle`). Play Console: USD 25 pago único.
- **iOS:** sin Mac, vía Codemagic (`codemagic.yaml`, workflow `ios`). Requiere Apple Developer
  (USD 99/año) y una clave App Store Connect API. Se prueba en iPhone real con TestFlight.

## Repositorio

El `.gitignore` excluye builds, dependencias (`node_modules`, `.dart_tool`), logs, carpetas locales
(`.claude/`), claves de firma Android y archivos de secretos. Los archivos de configuración de Firebase
para el cliente (`lib/firebase_options.dart`, `google-services.json`, `web/firebase-messaging-sw.js`) **sí**
se versionan: no son secretos, y la seguridad la dan las reglas de Firestore y Storage.
