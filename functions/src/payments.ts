/**
 * Proveedor de pagos intercambiable.
 *
 * - "mock" (por defecto): simula el checkout dentro de la propia app
 *   (/mock-checkout/:orderId). Sirve para desarrollar sin cuenta de Mercado Pago.
 * - "mercadopago": pendiente (ver ROADMAP.md). Creará una preferencia de
 *   Checkout Pro y devolverá su `init_point`; la confirmación llegará por webhook.
 *
 * Se elige con la variable de entorno PAYMENTS_PROVIDER (functions/.env).
 */
export interface CheckoutRequest {
  orderId: string;
  title: string;
  amount: number; // CLP, entero
  payerEmail?: string;
}

export interface Checkout {
  /** URL a la que se envía al cliente. Si empieza con "/" es una ruta interna de la app. */
  url: string;
  externalId?: string;
}

export interface PaymentProvider {
  readonly name: "mock" | "mercadopago";
  createCheckout(req: CheckoutRequest): Promise<Checkout>;
}

class MockPaymentProvider implements PaymentProvider {
  readonly name = "mock" as const;

  async createCheckout(req: CheckoutRequest): Promise<Checkout> {
    return { url: `/mock-checkout/${req.orderId}`, externalId: `mock_${req.orderId}` };
  }
}

export function paymentProvider(): PaymentProvider {
  const name = process.env.PAYMENTS_PROVIDER ?? "mock";
  switch (name) {
    case "mock":
      return new MockPaymentProvider();
    default:
      throw new Error(`Proveedor de pagos no soportado aún: ${name}`);
  }
}
