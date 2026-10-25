# Woowfy — Hoja de ruta

Marketplace de bolsas sorpresa contra el desperdicio de comida. Chile primero, luego Latam.
Marca las casillas a medida que avancemos. Última actualización: 10-10-2026 (ronda 8, tanda 3).

**En línea:** [woowfy.com](https://woowfy.com) (landing) · [app.woowfy.com](https://app.woowfy.com) (app)

## 📍 Dónde quedamos (10-10-2026)

**Lo técnico del piloto está completo.** Mercado Pago funciona de punta a punta con una cuenta de prueba (webhook
firmado + red de seguridad). Clientes: lista, mapa, favoritos, reserva, QR, cancelar (2 h antes o 15 min después
de pagar), calificar, impacto. Comercios: perfil, bolsas y recurrentes, cancelar bolsa, escáner QR propio (también
en iPhone), ventas, "Por recibir", cuenta bancaria y guía (`woowfy.com/merchants`). Admin: solicitudes, comercios,
liquidar / liquidar todos (planilla CSV), ventas, analítica anónima, interesados + modo lanzamiento de la landing,
usuarios y correo (plantillas de bienvenida, compra y reembolso). Auditoría del 28-09 corregida. Inicio de sesión con Google desde
`app.woowfy.com` ("Ir a woowfy.com"). Sprints 1–4 desplegados; la landing sigue "en construcción".

**Del 09 al 10-10:** tres críticas de diseño (Impeccable) y 8 rondas de arreglos: errores en español con
"Reintentar", modo mostrador, reglas de dinero antes de pagar, comprobante sin señal, Home con región y lista de
espera, landing honesta, admin con pestaña Pagos, liquidaciones que se pueden anular, retiro temprano con aviso.
Woowfy es un producto de **Passva SpA** (RUT 78.487.341-2), contacto `hola@passva.com`.

**Para retomar, primero lo que depende de ti** (sección "Pendiente" más abajo): probar el escáner en iPhone,
la revisión legal (Resend ya envía correos desde el 25-10). **Mercado Pago ya cobra en producción** con la cuenta de
Passva SpA (25-10): cada compra mueve dinero real. Con eso se puede lanzar (botón "Lanzar" arriba del admin).

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
- [x] **Push activo (25-10):** clave VAPID en `lib/core/push.dart`. En iPhone requiere instalar la app (Agregar a inicio)

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

**Etapa A2 — Segunda revisión de la auditoría (25-10) ✅** · probada en emuladores (17 pruebas)
- [x] #11 Pago que no calza con el pedido: se devuelve solo y queda anotado
- [x] Admin → Pagos → **"Requiere atención"**: reembolsos fallidos (antes nadie los veía) con botón "Reintentar"
- [x] #12 Límite de 2 reservas sin pagar también con compras en paralelo
- [x] #14 Código de retiro: si no carga, muestra el guardado en el teléfono o "Reintentar"
- [x] No-shows sin pisar un retiro recién validado · cuenta bancaria: se puede quitar y se validan todos los campos
      · el local ya no puede mover su ubicación en el mapa
- [x] #10 Producción revisada con `node tool/check-legacy-fields.mjs`: sin códigos de retiro ni correos expuestos
- [x] #13 El arrepentimiento de 15 min ya no aplica si el retiro empezó (rige la regla de 2 h); /terms y guía al día
- [ ] (Opcional) Activar TTL en `pickupCodes.expireAt` (consola → Firestore → TTL)

**Etapa B — Operación de pagos ✅**
- [x] Red de seguridad de pagos (el pedido se concilia con Mercado Pago si el aviso no llega)
- [x] Comisión visible siempre (25%): admin → Ventas, ventas del local, al publicar una bolsa y en el detalle para clientes
- [x] Decidido: **sí se le paga al local si el cliente no retira**. Pasado el horario (+60 min) el pedido queda
      "No retirado" (función `markNoShows`, cada 30 min), sin reembolso, y entra en la liquidación
- [x] "Liquidar todos" (Admin → Comercios) + planilla CSV con titular, RUT, banco, cuenta y monto por local
- [x] Datos bancarios del local en "Ventas y pagos" (privados: solo el dueño y el admin), con flujo visual de 3 pasos
      (Agrega tu cuenta → Vende y entrega → Te transferimos) también en la guía para comercios

**Etapa C — Piloto ✅** (salvo el correo de lanzamiento, que espera a Resend)
- [x] Correos de compra (con código de retiro) y de reembolso (con motivo): función `onOrderUpdated`, interruptor
      en Admin → Correo, **vista previa de plantillas sin enviar** y pruebas de cada tipo. Salen solos cuando actives Resend (vista previa: `node tool/preview-emails.mjs`)
- [x] Analítica básica propia y anónima (sin cookies): contadores por día en `stats/` + pestaña Admin → Analítica
      con visitas, inscritos, cuentas nuevas y embudo visita → bolsa vista → reserva → pago → retiro
- [x] Landing con modo lanzamiento: interruptor en Admin → Interesados (`config/site`), sin redesplegar
- [x] Correo de lanzamiento a la lista de espera: al presionar "Lanzar" se ofrece enviarlo (una vez por inscrito,
      con vista previa; sigue al día siguiente si se alcanza el tope diario de Resend). Función `sendLaunchEmails` (25-10)
- [x] Guía para comercios en `woowfy.com/merchants` (calculadora, consejos, retiros, cancelaciones, pagos) y enlace
      desde el panel del local

**Etapa D — Pagos divididos con Mercado Pago Marketplace** (después de la SpA; ver sección "Pagos divididos")
- [ ] Cada local conecta su cuenta de Mercado Pago; MP le deposita el 75% y a Woowfy el 25% en cada compra

### Diseño — crítica del 09-10 (Impeccable) · contexto en `PRODUCT.md`, crítica en `.impeccable/critique/`
Puntajes (heurísticas de Nielsen): Home 22/40 · flujo cliente 22/40 · comercio 22/40 · admin 23/40 · landing 20/32.

**Ronda 1 — bugs y errores rotos ✅** (probada en emuladores y desplegada el 09-10)
- [x] Botones y barra de navegación en Lato (salían en Roboto)
- [x] Errores legibles con "Reintentar" en toda la app (antes mostraban el error técnico en inglés)
- [x] Día real del retiro: "hoy / mañana / sáb 10 oct" en tarjeta, detalle, comprobante (con fecha), pedidos y panel
- [x] Precio al publicar acepta "3.500" (pone los puntos solo) y muestra el % de descuento; errores de horario específicos
- [x] `/merchants` en celular: la sección "Entregar" ya no se sale de la pantalla
- [x] "Sumar mi local" abre el formulario como comercio (`/?type=merchant#waitlist`)
- [x] Liquidar todos: vista previa con planilla copiable **antes** de registrar; los locales sin cuenta bancaria
      quedan fuera (también en el servidor) y no se puede cerrar sin aviso si no se copió la planilla final
- [x] Liquidar un local: muestra la cuenta de destino con botones para copiar; sin cuenta no se puede registrar
- [x] Interruptor de lanzamiento de la landing confirma o avisa si falla

**Ronda 2 — tanda A ✅** (primera visita del cliente; probada en emuladores y desplegada el 09-10)
- [x] Reglas de dinero antes de pagar (15 min, cancelar 2 h antes, sin retiro no hay reembolso) junto a "Reservar y pagar $X"; la comisión pasa a un plegable
- [x] Controles de la Home con texto: zona, orden visible y Lista/Mapa arriba; filtros abajo
- [x] Selector de región (todo Chile o una de las 16, con cuántas bolsas hay); se recuerda en el navegador. La ubicación se explica antes de pedirla y el mapa encuadra las bolsas (ya no supone Santiago)
- [x] Home vacía con salida: cómo funciona, "Avísame" (lista de espera de woowfy.com) y "¿Tienes un local?" (guía para comercios)

**Ronda 2 — tanda B ✅** (probada en emuladores y desplegada el 09-10)
- [x] Navegadores internos (Instagram, Facebook, TikTok, LinkedIn…): aviso con "Abrir en Chrome" (Android) o cómo abrir en el navegador y "Copiar enlace" (iPhone); queda el ingreso con correo. Si se bloquea la ventana de Google, sigue por redirección
- [x] Login con contexto ("Para reservar tu bolsa de {local}") y botón para ver la contraseña
- [x] Retomar la reserva: al ingresar vuelve a la bolsa con "Listo, ya ingresaste" y el botón destacado (un toque, nada se reserva solo)
- [x] Modo mostrador: cámara abierta, pantalla verde "Entrega: {bolsa} · Pagado $X" que sigue sola en 3 s, pantalla coral "No entregues" (ya retirado, código no válido, horario terminado) que espera un toque, vibración y "Por retirar: N"
- [x] Errores del servidor sin el sufijo técnico ("[404]") y "ya fue retirado" bien traducido

**Ronda 2 — tanda C ✅** (landing; desplegada el 09-10). Detector: de 34 a 24 hallazgos (los que quedan son decisiones de marca: Lato, crema, íconos en recuadro)
- [x] Aviso de lanzamiento tranquilo ("Abrimos pronto en todo Chile"), sin rayas ni punto que parpadea
- [x] Hero: maqueta con "Tu panadería de barrio" y "Ejemplo" (sin locales inventados), tarjeta con el reparto real (pagas / el local recibe / 25%) y "sin descargar nada"
- [x] Sin etiquetas sobre los títulos (home y /merchants), sin cinta animada, íconos en vez de emojis, "1/3" como frase con su fuente, secciones que ya no parten invisibles
- [x] Coral oscuro (#B83A22) para texto y etiquetas (contraste AA); círculo lima de /merchants ya no tapa el título en celular
- [x] Guía para comercios al día con el modo mostrador

**Segunda crítica (10-10):** Home 26/40 (antes 22) · cliente 23 (22) · comercio 25 (22) · admin 26 (23) · landing 21/32 (20) · detector en woowfy.com 10 hallazgos (21).

**Ronda 3 — confianza con el dinero ✅** (probada en emuladores y desplegada el 10-10)
- [x] Portada: "El local recibe $2.617" (misma cuenta que el servidor)
- [x] Nunca un $0 falso: esqueleto mientras carga y "Reintentar" si falla (Por recibir, Pagos recibidos, Por pagar del admin, cuenta bancaria)
- [x] "Por recibir" con "Ver detalle" de las ventas que lo componen
- [x] Calculadora de /merchants acepta "4.990", pone los puntos y avisa bajo $500
- [x] Reserva pendiente con reloj: en el comprobante, "Pagar en mm:ss" en Mis pedidos y "Ya tienes esta bolsa reservada · Completar pago" en el detalle
- [x] Reglas iguales en todas partes (incluye los 15 min después de pagar y 1 h después del horario) y plazo con día ("hasta hoy a las 16:00")
- [x] "Cancelar pedido" bajo "Más opciones", lejos del QR; errores legibles al cancelar y calificar; pedido inexistente con salida
- [x] Mostrador: "Entrega · 1 × {bolsa}" y "El cliente ya pagó $X en línea"; tono corto (también en iPhone); reintento inmediato tras un error de red
- [x] Admin: liquidar también locales suspendidos
- [x] RUT de la cuenta bancaria validado (dígito verificador) y guardado con formato

**Ronda 4 — primera visita ✅** (probada en emuladores y desplegada el 10-10)
- [x] Home sin bolsas: selector de región siempre visible, "Aún sin bolsas · {región}", "Sé de los primeros en {región}" y "Avísame" que abre la lista de espera con la región elegida (`woowfy.com/?region=`)
- [x] La lista se revisa cada minuto: las bolsas que cerraron desaparecen solas; título "Bolsas disponibles"; "Cierra en N min" en la tarjeta
- [x] Comprobante: el código, el local y el horario quedan guardados en el teléfono y se muestran si no hay conexión
- [x] Enlace de una bolsa que ya no está: "Esta bolsa ya se rescató o venció" con "Ver bolsas disponibles"
- [x] "Cerca de ti" en el selector; la región ya no se borra si falla el permiso de ubicación
- [x] Bolsa sin foto con ilustración "Bolsa sorpresa" (no un ícono de imagen rota); tarjeta que crece con letra grande
- [x] Login con contexto también para Mis pedidos, un pedido y el panel; la flecha vuelve a la bolsa
- [x] Controles de la Home de al menos 44 px

**Ronda 5 — comercio ✅** (probada en emuladores y desplegada el 10-10)
- [x] Panel ordenado por uso: bloque "Ahora · N por retirar" con "Validar retiro" grande, luego "Hoy y próximas", recurrentes, ventas y "Anteriores" plegadas; perfil con ícono de editar
- [x] "Mi local" en la barra de la app para quien tiene un local aprobado
- [x] Publicar "igual que ayer": el formulario parte con los datos (y la foto) de la última bolsa; "Publicar de nuevo" en cada bolsa
- [x] Editar bolsas (nombre, descripción, precios, sumar unidades) y recurrentes; con compradores, el horario queda fijo
- [x] Mientras te aprueban: checklist con logo y horario, cuenta bancaria y guía (plazo "normalmente 1 día hábil"); el envío de la solicitud ya no falla en silencio
- [x] Publicar no se cierra al tocar fuera; "Bolsa publicada · Ver como cliente"
- [x] Interruptores con nombre para lectores de pantalla; menú ⋮ con Editar, Publicar de nuevo y Cancelar

**Ronda 6 — landing ✅** (desplegada el 10-10)
- [x] Antes del lanzamiento, la lista de espera queda justo debajo del hero (ya lanzada, vuelve al final)
- [x] Guía para comercios coherente con el pre-lanzamiento: "Déjanos tus datos → Te contactamos"; ya lanzada, los pasos de la app
- [x] "Cuando haya bolsas en tu región" (antes "en tu comuna", que contradecía "todo Chile")
- [x] El código flotante ya no tapa "Quedan 2"; título del hero algo más chico; "Comercios" visible en el menú del celular
- [x] Errores del formulario: el campo se marca (aria-invalid) y recibe el foco
- [x] Tarjetas sin efecto de "levantarse"; aviso de privacidad de la cuenta sin duplicar

**Ronda 7 — admin ✅** (probada en emuladores y desplegada el 10-10, con reglas de Firestore)
- [x] Interesados: buscar por nombre, correo o comuna y "Borrar sus datos" (regla: solo admin puede borrar en `waitlist`)
- [x] Pestaña "Pagos": por pagar por local (también suspendidos), Liquidar todos e historial con "Copiar planilla"; Comercios queda para administrar locales
- [x] Aprobar, activar, suspender y rechazar con "Deshacer"
- [x] Analítica con error legible y Reintentar; insignias del correo de bienvenida con colores de la marca; Correo avisa cambios sin guardar
- [x] Cada pestaña con su URL (`/admin?tab=pagos`) y ayuda que se puede ocultar

**Tercera crítica (10-10):** Home 25/40 · cliente 28 (Bueno) · comercio 27 · admin 27 · landing 23/32 (Bueno) · detector 8 (todos de marca).

**Ronda 8, tanda 1 — base ✅** (desplegada el 10-10)
- [x] Lista de espera después del hero en el HTML (orden real para teclado y lectores); ya lanzada, site.js la mueve al final
- [x] Liquidaciones guardan la cuenta de destino; el historial copia la planilla con esa cuenta (las antiguas avisan que usan la actual)
- [x] Pantalla de carga con la marca mientras baja la app (antes, 3–5 s en blanco)
- [x] Semántica de Flutter activada desde el inicio (lectores de pantalla sin botón oculto)
- [x] Landing sin frases que suponen comercios existentes ("las bolsas vuelan", "los locales cuentan con…")

**Ronda 8, tanda 2 — cliente ✅** (desplegada el 10-10)
- [x] Home sin bolsas: título honesto ("Rescata comida en todo Chile") y lista de espera dentro de la app (sin salir a la landing; con sesión, nombre y correo ya escritos)
- [x] La función de lista de espera acepta envíos desde app.woowfy.com
- [x] Tarjeta de bolsa: comuna y región en su propia línea (antes se cortaba al final)
- [x] Pedido pagado: "¡Es tuya!" con lo pagado y lo ahorrado, "Cómo llegar" bajo el horario y ayuda con el pedido ya identificado (hola@passva.com)
- [x] Esperando pago: "Confirmando tu pago…" se revisa solo cada 15 s durante 1 minuto; cancelar queda abajo y discreto

**Ronda 8, tanda 3 — comercio y admin ✅** (desplegada el 10-10)
- [x] Local rechazado: ve el motivo y corrige sus datos en el mismo formulario antes de reenviar
- [x] Stock que sube y baja ("Quedan hoy" con − / +, en una transacción, nunca bajo 0); "igual que ayer" usa la cantidad de la última vez
- [x] Hora de retiro (desde 30 min antes): el botón flotante es "Validar retiro" y "Publicar" pasa a uno chico
- [x] Cliente temprano: el mostrador avisa en ámbar "Aún no es hora" con "Entregar igual"; al cliente se le pide llegar dentro del horario (antes de pagar, en el comprobante y en el correo)
- [x] Precio mínimo $500 en el formulario y en las reglas (bolsas y recurrentes)
- [x] Anular una liquidación (función voidPayout): sus ventas vuelven a "por pagar"; textos de "primero transfiere, después registra"
- [x] Aviso "en construcción · Lanzar" arriba de todo el admin; Ventas y Analítica parten en 7 días; la analítica no pasa de 100%

### Próximo (por decidir)
- [ ] Empleados por local, reclamos y moderación de opiniones, invitar amigos (referidos)

### Pendiente (depende de ti)
- [ ] 🔐 Verificación de marca en Google Auth Platform (opcional ahora: el inicio de sesión ya dice "Ir a woowfy.com")
- [ ] 📷 Probar el escáner QR nuevo en iPhone (Safari) con una compra de prueba
- [ ] 💸 Probar la liquidación: cuenta bancaria en *Ventas y pagos* y Admin → Pagos → "Liquidar todos" (si fue de prueba, "Anular")
- [ ] ✏️ Confirmar en la guía para comercios "pago semanal" y "aprobación en 1 día hábil" (y en los términos)
- [ ] Confirmar en tu navegador que al recargar `app.woowfy.com/merchant` sigues con sesión
- [x] 🔔 **Clave VAPID** para notificaciones push (25-10). Falta probar: Cuenta → Notificaciones → Activar, seguir un local
      y publicar una bolsa desde ese local (debe llegar el aviso)
- [x] ✉️ **Correos activos (25-10):** cuenta Resend (equipo passva), `woowfy.com` verificado en Piensa Solutions,
      clave "Woowfy Key" (solo envío) en `RESEND_API_KEY`, funciones redesplegadas e interruptor encendido en
      Admin → Correo. Prueba recibida en la bandeja de entrada desde `hola@woowfy.com`
- [x] ~~Reenvío `hola@woowfy.com` con ImprovMX~~: ya no hace falta, el contacto es `hola@passva.com` (10-10). TXT `_dmarc` agregado (25-10)
- [ ] 🗺️ Revisar el mapa en la app y poner la dirección real de tu local (hoy ubicado en el centro de El Monte)
- [ ] ⚖️ Revisión legal de `/terms` y `/privacy` (ya con los datos de Passva SpA; valores confirmados el 25-10:
      2 reservas, 2 h, 15 min, 25%, pago semanal). Consultar también quién emite la boleta al cliente
- [ ] 💰 **Alerta de presupuesto** en Google Cloud Billing (ej. USD 10)
- [ ] ↪️ Redirección 301 `www.woowfy.com` → `woowfy.com` (consola → Hosting → sitio woowfy-app → editar dominio)
- [x] `firebase functions:secrets:prune` (hecho el 10-10)
- [ ] Personalizar la plantilla del correo "recuperar contraseña" (Authentication → Plantillas)
- [ ] Enviar el aviso de lanzamiento cuando lances (sale del mismo botón "Lanzar"; también en Admin → Interesados)
- [ ] Pedir al diseñador un brand kit con el isotipo centrado (el v2 viene cortado)

### Resuelto en el camino
- [x] HTTPS en `woowfy.com`, `www` y `app`
- [x] `woowfy-app-web.web.app` en Dominios autorizados de Authentication
- [x] Usuario admin en producción y tu local "Woowfy App" aprobado
- [x] Fotos visibles en la app (CORS del bucket de Storage)
- [x] Imagen para compartir en redes (`og:image`) en la landing
- [x] Inicio de sesión con Google desde `app.woowfy.com` (Google muestra "Ir a woowfy.com")
- [x] Mercado Pago de prueba configurado (app Woowfy, token, clave del webhook regenerada, simulación 200)
- [x] Escáner QR en computador: usa la webcam, botón para cambiar de cámara y ayuda si no hay imagen
- [x] Admin: explicación breve en cada pestaña y contenido centrado
- [x] Escáner QR web propio (`web/qr_scanner.js`): capa HTML con cámara `playsinline` + BarcodeDetector/jsQR,
      mensajes por tipo de error y "Escribir el código". Probado leyendo un QR simulado; falta confirmarlo en iPhone

## Fase 2 — Pagos reales y operación

- [x] **SpA:** Woowfy es de **Passva SpA** (RUT 78.487.341-2), ver sección "Empresa" abajo
- [x] Cuenta Mercado Pago **a nombre de Passva SpA** con credenciales de producción en Secret Manager (25-10)
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

**Hoy:** Mercado Pago con credenciales de prueba (no se cobra dinero real). El siguiente paso es la cuenta de
Mercado Pago de Passva SpA; no usar un Mercado Pago personal para cobros reales.

| Opción | ¿Sirve para? | Comentario |
|---|---|---|
| **Mock** (emuladores) | Desarrollo y demos | Sin cuenta ni tokens. Se cambia a MP con `PAYMENTS_PROVIDER=mercadopago` |
| **Credenciales de prueba de MP** (actual) | Probar la integración real | En Mercado Pago Developers → *Tus integraciones* → crear aplicación → *Credenciales de prueba*. **No mueve dinero real.** Está bien usar tu cuenta personal solo para esto |
| MP personal en producción | ❌ No recomendado | Mezcla ingresos personales con los del negocio (problemas con el SII), no emite facturas a nombre de Woowfy, y el modelo marketplace requiere cuenta de empresa |
| **MP de la SpA** en producción | Cobros reales | El camino correcto cuando haya comercios reales |

---

## Empresa: constituir una SpA en Chile

**¿Es necesaria?** Para desarrollar y hacer demos, **no**. Para **cobrar dinero real**, firmar con
comercios y emitir facturas por la comisión, **sí** (o al menos iniciar actividades como persona natural,
pero la SpA separa tu patrimonio personal de los riesgos del negocio y es lo estándar para startups).

Pasos (con Clave Única):

**Estado (10-10):** la SpA ya existe: **Passva SpA**, RUT 78.487.341-2, Santiago (también dueña de passva.com).
Los pasos siguientes quedan por confirmar.

- [x] **1. Constituir la SpA** en [Registro de Empresas y Sociedades](https://www.registrodeempresasysociedades.cl)
      ("Tu Empresa en un Día"). Gratis, 100% online, puede tener un único socio.
      Define: razón social (ej. "Woowfy SpA"), giro, capital inicial, administración.
- [ ] **2. RUT (✅ 78.487.341-2) e inicio de actividades** (confirmar el giro de intermediación digital) en el [SII](https://www.sii.cl) — se puede hacer desde el mismo
      registro. Giro sugerido: servicios de intermediación a través de plataformas digitales
      (confirmar el código de actividad con tu contador).
- [ ] **3. Elegir régimen tributario** — normalmente **Pro Pyme** (general o transparente). Decidir con contador.
- [ ] **4. Facturación electrónica** en el SII (sistema gratuito): facturas de comisión a los comercios.
      Tu comisión está afecta a **IVA 19%**.
- [ ] **5. Cuenta bancaria** a nombre de la SpA (banco o banco digital para pymes).
- [ ] **6. Patente municipal** en la comuna del domicilio de la empresa (aunque sea tu casa u oficina virtual).
- [ ] **7. Contador** (aprox. CLP 30–80 mil/mes para una SpA pequeña): declaraciones mensuales (F29) y anual.
- [x] **8. Cuenta Mercado Pago de empresa** con el RUT de Passva SpA → credenciales de producción (25-10).
- [ ] **9. Marca "Woowfy" en [INAPI](https://www.inapi.cl)** (clases 35, 39/43 y 42) y dominio `woowfy.cl` en NIC Chile.
- [ ] **10. Contratos**: acuerdo con comercios (comisión, responsabilidad sanitaria del local, reembolsos)
      y T&C para clientes. Idealmente revisados por un abogado.

Costo inicial aproximado: constitución gratis; lo recurrente es contador + patente + marca.

---

## Cómo desarrollar y desplegar

Ver [README.md](README.md): emuladores, datos de prueba, comandos de deploy y dominios.
