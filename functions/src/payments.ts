import { createHmac, timingSafeEqual } from "node:crypto";
import { defineSecret } from "firebase-functions/params";

/**
 * Proveedor de pagos intercambiable (PAYMENTS_PROVIDER en functions/.env).
 *
 * - "mock": checkout simulado dentro de la app (/mock-checkout/:orderId). No mueve dinero.
 * - "mercadopago" (el activo hoy): Checkout Pro. createCheckout crea una "preferencia" y devuelve su URL de pago;
 *   la confirmación llega al webhook `mercadoPagoWebhook`. Usa las credenciales guardadas en
 *   Secret Manager (MP_ACCESS_TOKEN, MP_WEBHOOK_SECRET): con credenciales de PRUEBA no se cobra nada real.
 */
export const MP_ACCESS_TOKEN = defineSecret("MP_ACCESS_TOKEN");
export const MP_WEBHOOK_SECRET = defineSecret("MP_WEBHOOK_SECRET");
/** Secretos que deben declarar las funciones que usan el proveedor de pagos. */
export const PAYMENT_SECRETS = [MP_ACCESS_TOKEN, MP_WEBHOOK_SECRET];

const APP_URL = "https://app.woowfy.com";
const MP_API = "https://api.mercadopago.com";

export interface CheckoutRequest {
  orderId: string;
  title: string;
  amount: number; // CLP, entero
  payerEmail?: string;
  expiresAt: Date;
}

export interface Checkout {
  /** URL a la que se envía al cliente. Si empieza con "/" es una ruta interna de la app. */
  url: string;
  externalId?: string;
}

export interface PaymentProvider {
  readonly name: "mock" | "mercadopago";
  createCheckout(req: CheckoutRequest): Promise<Checkout>;
  /** Devuelve el dinero de un pago aprobado. Devuelve el id del reembolso. */
  refund(paymentId: string, orderId: string): Promise<string>;
}

class MockPaymentProvider implements PaymentProvider {
  readonly name = "mock" as const;

  async createCheckout(req: CheckoutRequest): Promise<Checkout> {
    return { url: `/mock-checkout/${req.orderId}`, externalId: `mock_${req.orderId}` };
  }

  async refund(_paymentId: string, orderId: string): Promise<string> {
    return `mock_refund_${orderId}`;
  }
}

class MercadoPagoProvider implements PaymentProvider {
  readonly name = "mercadopago" as const;

  private get token() {
    return MP_ACCESS_TOKEN.value();
  }

  private async api<T>(path: string, init: RequestInit & { idempotencyKey?: string } = {}): Promise<T> {
    const res = await fetch(`${MP_API}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
        ...(init.idempotencyKey ? { "X-Idempotency-Key": init.idempotencyKey } : {}),
      },
    });
    const body = (await res.json().catch(() => ({}))) as T & { message?: string };
    if (!res.ok) throw new Error(`Mercado Pago ${res.status}: ${body.message ?? JSON.stringify(body).slice(0, 200)}`);
    return body;
  }

  async createCheckout(req: CheckoutRequest): Promise<Checkout> {
    const back = `${APP_URL}/order/${req.orderId}`;
    const pref = await this.api<{ id: string; init_point: string; sandbox_init_point?: string }>("/checkout/preferences", {
      method: "POST",
      idempotencyKey: `pref_${req.orderId}`,
      body: JSON.stringify({
        items: [{ id: req.orderId, title: req.title, quantity: 1, unit_price: req.amount, currency_id: "CLP" }],
        payer: req.payerEmail ? { email: req.payerEmail } : undefined,
        external_reference: req.orderId,
        back_urls: { success: back, pending: back, failure: back },
        auto_return: "approved",
        notification_url: webhookUrl(),
        statement_descriptor: "WOOWFY",
        // La reserva dura 15 minutos: después, el link de pago deja de funcionar.
        expires: true,
        expiration_date_to: req.expiresAt.toISOString(),
      }),
    });
    const testMode = this.token.startsWith("TEST-");
    return { url: (testMode && pref.sandbox_init_point) || pref.init_point, externalId: pref.id };
  }

  async refund(paymentId: string, orderId: string): Promise<string> {
    const r = await this.api<{ id: number }>(`/v1/payments/${paymentId}/refunds`, {
      method: "POST",
      idempotencyKey: `refund_${orderId}`,
      body: "{}",
    });
    return String(r.id);
  }

  /** Consulta un pago (el webhook solo trae el id; el estado real se pide a la API). */
  getPayment(paymentId: string) {
    return this.api<{ id: number; status: string; external_reference?: string; transaction_amount: number }>(
      `/v1/payments/${paymentId}`,
    );
  }

  /** Último pago aprobado de un pedido (por external_reference). Sirve si el aviso del webhook no llegó. */
  async findApprovedPayment(orderId: string) {
    const r = await this.api<{ results?: Array<{ id: number; status: string; external_reference?: string; transaction_amount: number }> }>(
      `/v1/payments/search?external_reference=${encodeURIComponent(orderId)}&status=approved&sort=date_created&criteria=desc&limit=1`,
    );
    return r.results?.[0] ?? null;
  }
}

export function paymentProvider(): PaymentProvider {
  const name = process.env.PAYMENTS_PROVIDER ?? "mock";
  switch (name) {
    case "mock":
      return new MockPaymentProvider();
    case "mercadopago":
      return new MercadoPagoProvider();
    default:
      throw new Error(`Proveedor de pagos no soportado: ${name}`);
  }
}

export function mercadoPago(): MercadoPagoProvider {
  return new MercadoPagoProvider();
}

function webhookUrl() {
  const project = process.env.GCLOUD_PROJECT ?? "woowfy-app";
  return `https://southamerica-west1-${project}.cloudfunctions.net/mercadoPagoWebhook`;
}

/**
 * Verifica la firma del webhook de Mercado Pago (cabecera x-signature: "ts=...,v1=...").
 * Plantilla firmada: "id:{data.id};request-id:{x-request-id};ts:{ts};" con HMAC-SHA256 y la clave secreta.
 */
export function validMercadoPagoSignature(xSignature: string | undefined, xRequestId: string | undefined, dataId: string): boolean {
  const secret = MP_WEBHOOK_SECRET.value();
  if (!secret || secret.startsWith("pendiente")) return false;
  const parts = Object.fromEntries((xSignature ?? "").split(",").map((p) => p.trim().split("=") as [string, string]));
  if (!parts.ts || !parts.v1) return false;
  const manifest = `id:${dataId.toLowerCase()};${xRequestId ? `request-id:${xRequestId};` : ""}ts:${parts.ts};`;
  const expected = createHmac("sha256", secret).update(manifest).digest("hex");
  const a = Buffer.from(expected);
  const b = Buffer.from(parts.v1);
  return a.length === b.length && timingSafeEqual(a, b);
}
