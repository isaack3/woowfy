# Woowfy — Hoja de ruta

Marketplace de bolsas sorpresa contra el desperdicio de comida. Chile primero, luego Latam.
Marca las casillas a medida que avancemos. Última actualización: 28-09-2026 (Sprint 3).

**En línea:** [woowfy.com](https://woowfy.com) (landing) · [app.woowfy.com](https://app.woowfy.com) (app)

## 📍 Dónde quedamos (28-09-2026)

MVP técnico completo con pago **simulado** y Mercado Pago **listo para probar** con credenciales de prueba:
clientes (lista, mapa, favoritos, reserva, QR, cancelar con reembolso, calificar, impacto), comercios (perfil,
bolsas y recurrentes, cancelar bolsa, validar retiro con cámara, ventas y pagos) y admin (solicitudes,
comercios y liquidaciones, ventas, interesados, usuarios, correo). Sprints 1, 2 y 3 terminados y desplegados.
La landing está "en construcción" con lista de espera.

**Para retomar, primero lo que depende de ti** (sección "Pendiente" más abajo): credenciales de prueba de
Mercado Pago, clave VAPID, Resend e ImprovMX. Después: probar pagos de punta a punta con usuarios de prueba,
constituir la SpA y pasar a credenciales de producción.

---

## Cómo funciona el producto (el "por qué" de cada pieza)

```
 COMERCIO                      CLIENTE                         WOOWFY
 ────────                      ───────                         ──────
 1. Publica la bolsa del día ─► 2. La ve en la web/app
                                3. "Reservar y pagar" ───────► reserva 1 unidad (15 min)
                                4. Paga (Mercado Pago) ──────► confirma el pago
                                5. Recibe QR + código  ◄────── genera el comprobante
 6. En el local, el cliente muestra el QR
 7. El comercio valida el código ────────────────────────────► marca "retirado"
 8. Recibe su dinero (precio − comisión) ◄─────────────────── liquida al comercio
```

**¿Para qué sirve el QR?** Es el **comprobante de compra en el local**. Sin él, el comercio no
sabe si quien llega a buscar una bolsa realmente pagó, y alguien podría retirar dos veces o
retirar una bolsa ajena. Al validar el código:
- el comercio entrega solo bolsas pagadas, y cada una **una sola vez**;
- Woowfy sabe que la venta se completó (base para liquidar al comercio y para reclamos);
- el cliente tiene prueba de su compra si hay un problema.

El QR contiene el mismo código de 6 caracteres que aparece debajo: el comercio puede
**escanearlo con la cámara** o **tipearlo**.

---

## Fase 0 — Validación comercial (en paralelo al desarrollo)

- [ ] Visitar 30–40 locales en Providencia, Ñuñoa y Santiago Centro (panaderías, cafés, pastelerías)
- [ ] Conseguir 15 comercios dispuestos a probar
- [ ] Piloto manual (Instagram/WhatsApp + link de pago) para medir precio y demanda
- [ ] Validar la comisión (hoy configurada en 25% en `functions/src/orders.ts`)
- [ ] Revisar si existe competencia activa en Chile (Cheaf, Food To Save u otros)

## Fase 1 — MVP técnico

### Hecho ✅
- [x] Proyecto Flutter (web + Android + iOS) y Firebase `woowfy-app`
- [x] Firestore en Santiago (`southamerica-west1`), reglas de seguridad e índices
- [x] Inicio con bolsas del día (luego: todo Chile, con filtros, orden y mapa)
- [x] Registro / ingreso con correo
- [x] Panel del comercio: solicitud de alta, publicar bolsas, activar/pausar
- [x] Cloud Functions: reservar (con descuento de stock), pagar, cancelar, validar retiro
- [x] **Pago simulado (mock)** con la misma interfaz que usará Mercado Pago
- [x] Comprobante con **QR + código** y pantalla "Mis pedidos"
- [x] Comercio: "Por retirar" y **validar retiro** por código
- [x] Emuladores locales + datos de prueba (`npm --prefix functions run seed`)
- [x] **Panel admin** (`/admin`): aprobar/rechazar solicitudes, suspender/reactivar comercios (pausa sus bolsas), métricas de ventas y comisión
- [x] Landing y app publicadas en Firebase Hosting (`woowfy-app.web.app` y `woowfy-app-web.web.app`), guardando solo las últimas 5 versiones de cada sitio
- [x] Plan Blaze activado y Cloud Functions desplegadas (callables en Santiago; `expirePendingOrders`
      en São Paulo porque Cloud Scheduler no existe en Santiago). Imágenes viejas se borran a 1 día.
- [x] Landing estática en `landing/` (hero, cómo funciona, comercios, impacto, FAQ)
- [x] **Dominios propios** (DNS en Piensa Solutions): `woowfy.com` → landing, `www.woowfy.com` → landing,
      `app.woowfy.com` → app. Dominios autorizados en Firebase Authentication.

- [x] Identidad de marca (brand kit v2) aplicada en landing y app; íconos corregidos en `brand/fixed/`
- [x] Landing "en construcción" con **lista de espera** (región + comuna, todo Chile) y pestaña **Interesados** en el admin
- [x] Rutas de la app en inglés (`/bag`, `/login`, `/orders`, `/order`, `/merchant`, `/admin`)
- [x] Sin segmentar por comuna: la app muestra bolsas de todo Chile; locales e inscritos guardan región y comuna
- [x] Lista de espera con **nombre** (para campañas) y exportación CSV desde Admin → Interesados
- [x] Correo de bienvenida con Resend (función `onWaitlistCreated`) y remitente configurable en **Admin → Correo**
- [x] Recuperar contraseña, ingreso con Google y nombre en el registro
- [x] **Diseño A "Verde profundo"** en toda la app + navegación (Bolsas / Mis pedidos / Cuenta)
- [x] Fotos de bolsas (Firebase Storage, subida opcional al publicar) con ícono de "sin imagen" de respaldo
- [x] App en español de Chile (hora 24 h) y caché web corregida (cada deploy fuerza la versión nueva)

### Sprint 1 — listo para el piloto con locales ✅
- [x] Perfil del local: logo, categoría, descripción, horario (se copian a sus bolsas)
- [x] Bolsas recurrentes por día de la semana (se publican solas a las 5:00)
- [x] Escanear el QR con la cámara al validar retiros
- [x] Filtros en el inicio: categoría, "retiro ahora", orden por horario / precio / descuento
- [x] Admin → Usuarios: buscar y dar o quitar admin
- [x] Borradores de Términos y Política de privacidad (`/terms`, `/privacy`)

### Sprint 2 — retención ✅
- [x] Mapa (OpenStreetMap) y orden "Más cerca" con distancia en cada bolsa
- [x] Favoritos (seguir locales) + filtro, y aviso push cuando publican
- [x] Recordatorio push antes del horario de retiro
- [x] Tu impacto (bolsas rescatadas, ahorro, CO₂ evitado estimado)
- [x] Compartir bolsa (menú nativo o copiar enlace)
- [x] Instalar la app (PWA) desde Cuenta
- [ ] **Activar push:** generar la clave VAPID en la consola y ponerla en `lib/core/push.dart`

### Sprint 3 — confianza y operación ✅
- [x] Calificar el retiro (1–5 estrellas y comentario), nota del local en tarjetas y detalle, opiniones
- [x] Cancelar pedido hasta 2 horas antes, con reembolso automático
- [x] El comercio cancela la bolsa del día: reembolso y aviso push a los compradores
- [x] Ventas y pagos del comercio (`/merchant/sales`) y liquidaciones desde Admin → Comercios → Liquidar
- [x] Mercado Pago Checkout Pro + webhook firmado + reembolsos (listo, falta cargar credenciales de prueba)
- [x] Arreglo: al abrir directo una ruta protegida ya no manda al login si hay sesión

### Sprint 4 — listo para el piloto (en curso)

**Etapa A — Auditoría del 28-09 (dinero y reglas) ✅** · ver `AUDITORIA-2026-09-28.md` · probada en emuladores (16 pruebas)
y desplegada el 28-09; datos de producción migrados
- [x] A1 · #5 El comercio cancela la bolsa: cada pedido se cancela releyendo su estado (no se pierde ningún reembolso)
- [x] A2 · #4 Precio válido también al editar una bolsa, y revisado otra vez en el servidor al comprar
- [x] A3 · #3 Un local no puede crearse con calificación ni campos internos
- [x] A4 · #2 El correo del dueño deja de estar en el local público (el admin lo ve desde su cuenta)
- [x] A5 · #7 Misma verificación de monto en webhook y conciliación
- [x] A6 · #9 Solo se compra si el local sigue aprobado
- [x] A7 · #6 Máximo 2 reservas sin pagar por persona
- [x] A8 · #8 Liquidación atómica (sin duplicados por doble clic)
- [x] A9 · #1 Código de retiro privado: solo lo ve el cliente; el comercio lo valida cuando se lo muestran
- [x] A10 · Menores: recordatorios acotados y comentarios al día (queda aceptado: subidas a Storage de cualquier
      usuario con sesión y sin ventana de antigüedad en la firma del webhook; bajo impacto)
- [x] A11 · Arrepentimiento: cancelar con reembolso hasta 15 min después de pagar (además de las 2 h antes del retiro)

**Etapa B — Operación de pagos ✅**
- [x] Red de seguridad de pagos (el pedido se concilia con Mercado Pago si el aviso no llega)
- [x] Comisión visible siempre (25%): admin → Ventas, ventas del local, al publicar una bolsa y en el detalle para clientes
- [x] Decidido: **sí se le paga al local si el cliente no retira**. Pasado el horario (+60 min) el pedido queda
      "No retirado" (función `markNoShows`, cada 30 min), sin reembolso, y entra en la liquidación
- [x] "Liquidar todos" (Admin → Comercios) + planilla CSV con titular, RUT, banco, cuenta y monto por local
- [x] Datos bancarios del local en "Ventas y pagos" (privados: solo el dueño y el admin)

**Etapa C — Piloto**
- [ ] Correos de confirmación de compra y de reembolso (salen cuando Resend esté activo)
- [x] Analítica básica propia y anónima (sin cookies): contadores por día en `stats/` + pestaña Admin → Analítica
      con visitas, inscritos, cuentas nuevas y embudo visita → bolsa vista → reserva → pago → retiro
- [x] Landing con modo lanzamiento: interruptor en Admin → Interesados (`config/site`), sin redesplegar
- [ ] Correo de lanzamiento a la lista de espera (cuando Resend esté activo)
- [x] Guía para comercios en `woowfy.com/merchants` (calculadora, consejos, retiros, cancelaciones, pagos) y enlace
      desde el panel del local

**Etapa D — Pagos divididos con Mercado Pago Marketplace** (después de la SpA; ver sección "Pagos divididos")
- [ ] Cada local conecta su cuenta de Mercado Pago; MP le deposita el 75% y a Woowfy el 25% en cada compra

### Próximo (por decidir)
- [ ] Empleados por local, reclamos y moderación de opiniones, invitar amigos (referidos)

### Pendiente (depende de ti)
- [ ] Confirmar en tu navegador que al recargar `app.woowfy.com/merchant` sigues con sesión
- [ ] 🔔 **Clave VAPID** para notificaciones push: consola Firebase → Configuración del proyecto → Cloud Messaging
      → Certificados push web → Generar. La clave pública va en `lib/core/push.dart` y se redespliega la app.
- [ ] ✉️ **Activar correos:** cuenta Resend + verificar `woowfy.com` (DNS en Piensa Solutions) +
      `firebase functions:secrets:set RESEND_API_KEY` + redeploy de las funciones de correo + activar en
      Admin → Correo (hoy el secreto tiene un valor provisional)
- [ ] 📥 Reenvío `hola@woowfy.com` → Gmail con ImprovMX (MX `mx1/mx2.improvmx.com`, TXT SPF) y TXT `_dmarc`
- [ ] 🗺️ Revisar el mapa en la app y poner la dirección real de tu local (hoy ubicado en el centro de El Monte)
- [ ] ⚖️ Revisión legal de `/terms` y `/privacy` y completar datos de la SpA (razón social, RUT, domicilio)
- [ ] 💰 **Alerta de presupuesto** en Google Cloud Billing (ej. USD 10)
- [ ] ↪️ Redirección 301 `www.woowfy.com` → `woowfy.com` (consola → Hosting → sitio woowfy-app → editar dominio)
- [ ] Personalizar la plantilla del correo "recuperar contraseña" (Authentication → Plantillas)
- [ ] Correo de lanzamiento a la lista de espera (exportar CSV desde Admin → Interesados)
- [ ] Pedir al diseñador un brand kit con el isotipo centrado (el v2 viene cortado)

### Resuelto en el camino
- [x] HTTPS en `woowfy.com`, `www` y `app`
- [x] `woowfy-app-web.web.app` en Dominios autorizados de Authentication
- [x] Usuario admin en producción y tu local "Woowfy App" aprobado
- [x] Fotos visibles en la app (CORS del bucket de Storage)
- [x] Imagen para compartir en redes (`og:image`) en la landing
- [x] Mercado Pago de prueba configurado (app Woowfy, token, clave del webhook regenerada, simulación 200)
- [x] Escáner QR en computador: usa la webcam, botón para cambiar de cámara y ayuda si no hay imagen
- [x] Admin: explicación breve en cada pestaña y contenido centrado
- [x] Escáner QR en iPhone: el video de la cámara necesita `playsinline` (arreglo en `web/index.html`) + botón Reintentar

## Fase 2 — Pagos reales y operación

- [ ] **Constituir la SpA** (ver sección "Empresa" abajo) ← bloquea el cobro real
- [ ] Cuenta Mercado Pago **a nombre de la SpA**
- [x] Implementar `MercadoPagoProvider` (Checkout Pro) + webhook `mercadoPagoWebhook` firmado + reembolsos (Sprint 3)
- [x] Probar con **credenciales de prueba** de Mercado Pago: compra de punta a punta OK (28-09)
- [ ] Definir cómo se paga a los comercios:
      - Opción A: **Split de Mercado Pago (Marketplace)** — cada comercio conecta su cuenta MP y
        recibe su parte directo; Woowfy cobra `marketplace_fee`. Más limpio contable y legalmente.
      - Opción B: todo entra a la SpA y se liquida semanalmente por transferencia. Más simple al inicio,
        pero la SpA maneja dinero de terceros (revisar con contador).
- [x] Reembolsos: cancelación del cliente, del comercio y pagos tardíos (Sprint 3)
- [x] Escanear QR con la cámara en el panel del comercio (Sprint 1)
- [x] Notificaciones "tu favorito publicó bolsas" y recordatorio de retiro (Sprint 2; falta la clave VAPID)
- [ ] Correo de confirmación de compra (cuando Resend esté activo)
- [x] Favoritos (Sprint 2)
- [x] Ventas y liquidaciones para el comercio (Sprint 3)

## Fase 3 — Tracción y apps móviles

- [ ] 50–100 comercios activos
- [ ] Íconos de Android/iOS con `flutter_launcher_icons` usando `brand/fixed/icon-1024.png`
- [ ] Android en Google Play (compila desde Windows; USD 25 pago único)
- [ ] iOS vía Codemagic (`codemagic.yaml`; Apple Developer USD 99/año; pruebas en TestFlight)
- [x] Mapa y orden por cercanía (Sprint 2)
- [ ] Consultas por cercanía en el servidor (geohash) cuando haya muchos locales
- [ ] Plan pagado para comercios (destacados, reportes de impacto)
- [ ] Filtro por región/cercanía cuando haya suficientes locales

## Fase 4 — Latam

- [ ] Perú y Colombia (socio local, Mercado Pago disponible en ambos)
- [ ] México
- [ ] Multi-moneda, impuestos y textos por país

---

## Pagos divididos (Mercado Pago Marketplace) — plan, aún no implementado

Hoy todo el dinero entra a la cuenta de Woowfy y se liquida a mano a cada local. Con **Marketplace**, cada compra se
divide sola: Mercado Pago deposita el 75% en la cuenta del local y cobra el 25% (`marketplace_fee`) para Woowfy.

1. **Requisitos:** SpA constituida, cuenta MP de la SpA y aplicación en modo Marketplace; cada local con cuenta MP.
2. **Conectar al local (OAuth):** en su panel, botón "Conectar Mercado Pago" → autoriza a Woowfy en MP → vuelve
   a una función `mpOAuthCallback` que cambia el código por un `access_token` + `refresh_token` **del local**.
   Se guardan cifrados en un documento solo para el servidor (`stores/{id}/private/mercadopago`); el local ve
   "Conectado como …". Un job renueva los tokens antes de que venzan (duran ~180 días).
3. **Cobrar:** `createOrder` crea la preferencia **con el token del local** e incluye `marketplace_fee` = comisión.
   El pago queda en la cuenta del local, y MP transfiere la comisión a Woowfy. El webhook y la conciliación
   siguen igual (consultan el pago con el token del local).
4. **Reembolsos:** se hacen con el token del local; MP devuelve también la comisión proporcional.
5. **Transición:** locales sin cuenta conectada siguen con el flujo actual (cobro en Woowfy + liquidación manual),
   así se puede migrar de a uno. "Liquidar" solo se usa para esos locales.
6. **Ventajas:** no hay transferencias manuales, Woowfy no custodia dinero de terceros y cada uno tributa lo suyo
   (Woowfy factura solo su comisión). **Costos:** la comisión de MP la paga el local sobre su venta (conviene
   explicarlo en el contrato).
7. **Esfuerzo estimado:** 1 sprint (OAuth + tokens + preferencia con token del local + panel "Conectar" + pruebas
   con usuarios de prueba vendedor/comprador).

## Pagos: ¿mock, MP personal o SpA?

**Recomendación: seguir con el mock ahora** (ya implementado) y no usar tu Mercado Pago personal
para cobros reales.

| Opción | ¿Sirve para? | Comentario |
|---|---|---|
| **Mock (actual)** | Desarrollo y demos | Sin cuenta ni tokens. Se cambia a MP con `PAYMENTS_PROVIDER=mercadopago` |
| **Credenciales de prueba de MP** (cuenta personal) | Probar la integración real | En Mercado Pago Developers → *Tus integraciones* → crear aplicación → *Credenciales de prueba*. **No mueve dinero real.** Está bien usar tu cuenta personal solo para esto |
| MP personal en producción | ❌ No recomendado | Mezcla ingresos personales con los del negocio (problemas con el SII), no emite facturas a nombre de Woowfy, y el modelo marketplace requiere cuenta de empresa |
| **MP de la SpA** en producción | Cobros reales | El camino correcto cuando haya comercios reales |

---

## Empresa: constituir una SpA en Chile

**¿Es necesaria?** Para desarrollar y hacer demos, **no**. Para **cobrar dinero real**, firmar con
comercios y emitir facturas por la comisión, **sí** (o al menos iniciar actividades como persona natural,
pero la SpA separa tu patrimonio personal de los riesgos del negocio y es lo estándar para startups).

Pasos (con Clave Única):

- [ ] **1. Constituir la SpA** en [Registro de Empresas y Sociedades](https://www.registrodeempresasysociedades.cl)
      ("Tu Empresa en un Día"). Gratis, 100% online, puede tener un único socio.
      Define: razón social (ej. "Woowfy SpA"), giro, capital inicial, administración.
- [ ] **2. RUT e inicio de actividades** en el [SII](https://www.sii.cl) — se puede hacer desde el mismo
      registro. Giro sugerido: servicios de intermediación a través de plataformas digitales
      (confirmar el código de actividad con tu contador).
- [ ] **3. Elegir régimen tributario** — normalmente **Pro Pyme** (general o transparente). Decidir con contador.
- [ ] **4. Facturación electrónica** en el SII (sistema gratuito): facturas de comisión a los comercios.
      Tu comisión está afecta a **IVA 19%**.
- [ ] **5. Cuenta bancaria** a nombre de la SpA (banco o banco digital para pymes).
- [ ] **6. Patente municipal** en la comuna del domicilio de la empresa (aunque sea tu casa u oficina virtual).
- [ ] **7. Contador** (aprox. CLP 30–80 mil/mes para una SpA pequeña): declaraciones mensuales (F29) y anual.
- [ ] **8. Cuenta Mercado Pago de empresa** con el RUT de la SpA → credenciales de producción.
- [ ] **9. Marca "Woowfy" en [INAPI](https://www.inapi.cl)** (clases 35, 39/43 y 42) y dominio `woowfy.cl` en NIC Chile.
- [ ] **10. Contratos**: acuerdo con comercios (comisión, responsabilidad sanitaria del local, reembolsos)
      y T&C para clientes. Idealmente revisados por un abogado.

Costo inicial aproximado: constitución gratis; lo recurrente es contador + patente + marca.

---

## Cómo desarrollar y desplegar

Ver [README.md](README.md): emuladores, datos de prueba, comandos de deploy y dominios.
