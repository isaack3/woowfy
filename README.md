# Woowfy

Marketplace de **bolsas sorpresa** contra el desperdicio de comida: los locales publican lo que no
vendieron en el día, los clientes lo reservan y pagan en línea, y lo retiran con un código QR.
Chile primero, luego Latam.

- **Landing:** https://woowfy.com
- **App:** https://app.woowfy.com
- **Hoja de ruta y estado:** [ROADMAP.md](ROADMAP.md)

## Stack

| Parte | Tecnología |
|---|---|
| App (web hoy; Android/iOS después) | Flutter · go_router · Material 3 |
| Landing | HTML + CSS estático (`landing/`), pensado para SEO |
| Backend | Firebase: Auth, Firestore, Cloud Functions (TypeScript, Node 22), Hosting |
| Pagos | Proveedor intercambiable: `mock` hoy, Mercado Pago después |
| Builds móviles | Codemagic (`codemagic.yaml`), para compilar iOS sin Mac |

Proyecto Firebase: **`woowfy-app`** (plan Blaze). Paquete Android / Bundle iOS: `com.woowfy.woowfy`.

## Estructura

```
lib/
  main.dart, app.dart
  core/          tema, router, formato CLP, backend (emuladores/región), checkout
  data/          modelos (Bag, Store, BagOrder) y repositorio Firestore/Functions
  features/
    home/        bolsas del día por comuna
    bags/        tarjeta, detalle y botón "Reservar y pagar"
    auth/        ingreso / registro con correo
    orders/      checkout simulado, comprobante con QR, "Mis pedidos"
    merchant/    panel del comercio: solicitud de alta, publicar bolsas, validar retiros
    admin/       panel admin: solicitudes, comercios, ventas
functions/
  src/orders.ts      createOrder, confirmMockPayment, redeemOrder, expirePendingOrders
  src/payments.ts    interfaz PaymentProvider (mock | mercadopago)
  scripts/seed-emulators.mjs   datos y cuentas de prueba para los emuladores
landing/index.html   landing de woowfy.com
firestore.rules, firestore.indexes.json
```

## Modelo de datos (Firestore)

| Colección | Contenido | Quién escribe |
|---|---|---|
| `users/{uid}` | email, `role` (`customer` \| `admin`) | el usuario (solo `customer`); admin |
| `stores/{id}` | local; `status`: `pending` → `approved` / `rejected` / `suspended` | el dueño crea; admin cambia el estado |
| `bags/{id}` | bolsa del día: precio, stock, horario de retiro | comercio aprobado; admin puede pausar |
| `orders/{id}` | compra: estado, monto, comisión, código de retiro | **solo Cloud Functions** |

Estados de un pedido: `pending_payment` (bolsa reservada 15 min) → `paid` (muestra QR) →
`picked_up` (el comercio validó el código). Si no se paga a tiempo o se rechaza: `cancelled` y el
stock vuelve a la bolsa.

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
- Emulator UI: http://127.0.0.1:4000
- Los datos del emulador se borran al cerrarlo: vuelve a correr el `seed`.
- `expirePendingOrders` (tarea programada) no se ejecuta en el emulador.
- Si al iniciar dice que los puertos 4000/8080/9099 están ocupados, quedó un emulador anterior
  abierto: ciérralo antes de volver a iniciarlo.

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

Hosting guarda solo las **últimas 5 versiones** de cada sitio y las imágenes de las functions se
borran a 1 día, para no acumular deploys viejos.

| Qué | Comando |
|---|---|
| Reglas e índices | `firebase deploy --only firestore` |
| Cloud Functions | `firebase deploy --only functions` |
| Landing | `firebase deploy --only hosting:landing` |
| App | `flutter build web --release` y luego `firebase deploy --only hosting:app` |

> Nunca despliegues `build/web-emulators`: es un build que apunta a los emuladores.

Regiones: Firestore y las funciones *callable* en **Santiago** (`southamerica-west1`);
`expirePendingOrders` en **São Paulo** (`southamerica-east1`) porque Cloud Scheduler no existe en Santiago.

## Dominios

DNS administrado en **Piensa Solutions**.

| Dominio | Registro DNS | Sitio de Firebase Hosting |
|---|---|---|
| `woowfy.com` | A `199.36.158.100` + TXT `hosting-site=woowfy-app` | `woowfy-app` (landing) |
| `www.woowfy.com` | CNAME `woowfy-app.web.app` | `woowfy-app` (landing) |
| `app.woowfy.com` | CNAME `woowfy-app-web.web.app` | `woowfy-app-web` (app) |

Un nombre con CNAME no puede tener otros registros, y el dominio raíz (`@`) no admite CNAME.
El TXT `google-site-verification` es de Google Search Console: no borrarlo.

La landing detecta dónde corre: en `woowfy.com` sus botones llevan a `app.woowfy.com`; en
`*.web.app` llevan a `woowfy-app-web.web.app`; en `localhost`, a la app local.

## Administración

- **Hacerte admin en producción:** regístrate en la app y, en la consola de Firestore, cambia `role` a
  `admin` en tu documento `users/{uid}`. Aparecerá el botón **Admin** (`/admin`).
- **Aprobar comercios:** Admin → Solicitudes.

## Pagos

`functions/.env` → `PAYMENTS_PROVIDER=mock`: el checkout es simulado y no mueve dinero. Para Mercado Pago
ver ROADMAP (Fase 2). Los tokens van en Secret Manager (`firebase functions:secrets:set`), **nunca** en
archivos del repositorio.

## Móviles (más adelante)

- **Android:** se compila desde Windows (`flutter build appbundle`). Play Console: USD 25 pago único.
- **iOS:** sin Mac, vía Codemagic (`codemagic.yaml`, workflow `ios`). Requiere Apple Developer
  (USD 99/año) y una clave App Store Connect API. Se prueba en iPhone real con TestFlight.

## Repositorio

El `.gitignore` excluye builds, dependencias (`node_modules`, `.dart_tool`), logs, carpetas locales
(`.claude/`), claves de firma Android y archivos de secretos. Los archivos de configuración de Firebase
para el cliente (`lib/firebase_options.dart`, `google-services.json`) **sí** se versionan: no son
secretos, y la seguridad la dan las reglas de Firestore.
