# Woowfy — Hoja de ruta

Marketplace de bolsas sorpresa contra el desperdicio de comida. Chile primero, luego Latam.
Marca las casillas a medida que avancemos. Última actualización: 27-09-2026.

**En línea:** [woowfy.com](https://woowfy.com) (landing) · [app.woowfy.com](https://app.woowfy.com) (app)

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
**tipearlo** (ya funciona) o **escanearlo con la cámara** (pendiente, Fase 2).

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
- [x] Inicio con bolsas del día y filtro por comuna
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

### Pendiente
- [ ] Confirmar HTTPS en `woowfy.com` (el certificado se estaba emitiendo al 27-09-2026)
- [ ] Redirección 301 `www.woowfy.com` → `woowfy.com` (consola → Hosting → sitio woowfy-app → editar dominio)
- [ ] Agregar `woowfy-app-web.web.app` a Dominios autorizados de Authentication
- [ ] Configurar una **alerta de presupuesto** en Google Cloud Billing (ej. USD 10)
- [ ] Crear tu usuario admin en producción (ver README)
- [ ] Primer commit y subir el repositorio (el `.gitignore` ya excluye builds, dependencias y secretos)
- [ ] Recuperar contraseña e ingreso con Google
- [ ] Términos y Condiciones, Política de Privacidad (Ley 21.719) y política de cancelación
- [ ] Imagen para compartir en redes (og:image 1200×630) y crear casilla `hola@woowfy.com`
      (el dominio aún no tiene registros MX de correo)

## Fase 2 — Pagos reales y operación

- [ ] **Constituir la SpA** (ver sección "Empresa" abajo) ← bloquea el cobro real
- [ ] Cuenta Mercado Pago **a nombre de la SpA**
- [ ] Implementar `MercadoPagoProvider` en `functions/src/payments.ts` (Checkout Pro) +
      webhook `mercadoPagoWebhook` que llama a `markOrderPaid`
- [ ] Probar con **credenciales de prueba** de Mercado Pago (ver "Pagos" abajo)
- [ ] Definir cómo se paga a los comercios:
      - Opción A: **Split de Mercado Pago (Marketplace)** — cada comercio conecta su cuenta MP y
        recibe su parte directo; Woowfy cobra `marketplace_fee`. Más limpio contable y legalmente.
      - Opción B: todo entra a la SpA y se liquida semanalmente por transferencia. Más simple al inicio,
        pero la SpA maneja dinero de terceros (revisar con contador).
- [ ] Reembolsos (bolsa no entregada / local cerrado)
- [ ] Escanear QR con la cámara en el panel del comercio (`mobile_scanner`, funciona en web)
- [ ] Notificaciones: "tu favorito publicó bolsas" (web push / FCM) y correo de confirmación
- [ ] Favoritos
- [ ] Reportes para el comercio (ventas, kg rescatados, liquidaciones)

## Fase 3 — Tracción y apps móviles

- [ ] 50–100 comercios activos en 5 comunas
- [ ] Android en Google Play (compila desde Windows; USD 25 pago único)
- [ ] iOS vía Codemagic (`codemagic.yaml`; Apple Developer USD 99/año; pruebas en TestFlight)
- [ ] Búsqueda por cercanía (geohash) y mapa
- [ ] Plan pagado para comercios (destacados, reportes de impacto)
- [ ] Nuevas ciudades: Viña/Valparaíso, Concepción

## Fase 4 — Latam

- [ ] Perú y Colombia (socio local, Mercado Pago disponible en ambos)
- [ ] México
- [ ] Multi-moneda, impuestos y textos por país

---

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
