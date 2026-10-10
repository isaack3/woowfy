# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Una sola identidad Woowfy (Flutter + Material 3 con la marca) en web, Android e iOS; no se adapta a Cupertino en iPhone. Hoy solo está publicada la web (`app.woowfy.com`, instalable como PWA); Android e iOS vienen después (iOS compilado con Codemagic).

## Users

Dos perfiles con el mismo peso; cada pantalla se optimiza para el suyo, sin que uno mande sobre el otro.

- **Cliente que rescata:** persona en Chile que, desde el celular y casi siempre sin instalar una app, busca bolsas sorpresa de comida a mitad de precio cerca de ella, reserva y paga en línea, y la retira en el local mostrando un QR dentro de un horario acotado.
- **Comercio:** panadería, café, pastelería u otro local de comida que publica lo que no vendió en el día (o bolsas recurrentes), valida retiros escaneando o tipeando el código, y revisa sus ventas y pagos. Suele operar desde el mostrador, con prisa y con el cliente esperando.
- **Admin (equipo Woowfy):** aprueba comercios, liquida ventas, revisa analítica e interesados, lanza la landing y gestiona usuarios y correos.

## Product Purpose

Marketplace de bolsas sorpresa contra el desperdicio de comida: los locales recuperan algo de lo que iban a botar, los clientes comen rico a mitad de precio y se evita desperdicio. Chile primero, luego Latam. Éxito = bolsas publicadas que se venden y se retiran, comercios que vuelven a publicar y liquidaciones correctas.

## Positioning

Frente a Too Good To Go, Cheaf o Food To Save, lo confirmado hasta ahora:

- **Sin instalar app:** funciona completo en el navegador (web/PWA), porque en Chile mucha gente no instala apps.
- **Todo Chile:** no segmenta por comuna; muestra bolsas de las 16 regiones desde el inicio.
- **Trato claro al local:** comisión visible siempre (25%), pago semanal y se le paga al local aunque el cliente no retire.

Decisión abierta: el usuario aún no define si estos tres puntos son el posicionamiento final o si falta una diferencia más fuerte.

## Operating Context

- Flujo: el comercio publica la bolsa → el cliente la ve (lista o mapa) → "Reservar y pagar" (reserva 15 min) → paga con Mercado Pago → recibe QR + código de 6 caracteres → lo muestra en el local → el comercio lo valida → Woowfy liquida al comercio (precio − comisión).
- Reglas visibles para el cliente: máximo 2 reservas sin pagar; cancelar con reembolso hasta 2 h antes del retiro o 15 min después de pagar; pasado el horario (+60 min) el pedido queda "No retirado", sin reembolso.
- El comercio puede cancelar la bolsa del día (reembolso y aviso push a compradores).
- Calificación 1–5 tras retirar; nota del local visible en tarjetas y detalle.
- Correos transaccionales (bienvenida, compra, reembolso) vía Resend; push vía FCM (pendiente clave VAPID).
- Landing `woowfy.com` en modo "en construcción" con lista de espera; se lanza con un interruptor en Admin → Interesados.

## Capabilities and Constraints

- App: Flutter Web (Material 3, go_router, flutter_map/OpenStreetMap). Landing: HTML + CSS estático en `landing/`. Backend: Firebase (`woowfy-app`, `southamerica-west1`).
- Rutas en inglés; todo texto visible en **español de Chile**, hora 24 h, montos en CLP.
- Formularios piden **región** (16) + **comuna** (texto); nunca se filtra la app por comuna.
- Pagos: proveedor intercambiable (`mock` / Mercado Pago). Producción depende de constituir la SpA.
- Términos de dominio: "bolsa", "rescatar", "retiro", "código de retiro", "Por retirar", "No retirado", "liquidar", "comercio"/"local".
- Abierto: textos legales (/terms, /privacy) son borradores sin revisión legal; la comisión de 25% está por validar con comercios.

## Brand Commitments

- Nombre **Woowfy**. Brand kit v2 en `brand/` (logos SVG/PNG, íconos, OG, brand board, colores); el isotipo del kit viene descentrado, usar `brand/fixed/`.
- Voz: cercana, en "tú", español de Chile, directa (ej. "Rescata comida rica a mitad de precio").
- Paleta oficial e identidad visual: ver brand kit; las decisiones visuales viven fuera de este archivo.

## Evidence on Hand

- Producto funcionando de punta a punta con Mercado Pago de prueba (ROADMAP.md, Sprints 1–4).
- Guía para comercios con calculadora: `landing/merchants.html`.
- Analítica propia anónima (Admin → Analítica) y lista de espera real (Admin → Interesados).
- **No existen todavía:** comercios activos, testimonios, reseñas reales, cifras de impacto reales, prensa ni casos. No inventarlos.

## Product Principles

1. **Funciona sin instalar nada:** cada flujo debe completarse bien en el navegador del celular.
2. **Dos lados iguales:** cliente y comercio pesan lo mismo; lo que simplifica a uno no puede complicar al otro.
3. **Reglas claras y visibles:** precio, comisión, horarios de retiro, cancelación y reembolsos se dicen antes de pagar, no después.
4. **Rápido en el mostrador:** validar un retiro y publicar una bolsa debe tomar segundos.
5. **Todo Chile, en chileno:** nada de suponer Santiago ni de usar español neutro.
