import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Comprobante del pedido. Cuando está pagado muestra el QR/código que el
/// cliente presenta en el local para retirar su bolsa.
class OrderPage extends StatelessWidget {
  const OrderPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu pedido'),
        leading: BackButton(onPressed: () => context.go('/pedidos')),
      ),
      body: StreamBuilder<BagOrder?>(
        stream: Repository.instance.watchOrder(orderId),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('No pudimos cargar el pedido.'));
          final order = snap.data;
          if (order == null) return const Center(child: CircularProgressIndicator());
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [_Body(order: order)],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pickup = 'Retiro ${formatPickupWindow(order.pickupStart, order.pickupEnd)}';

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.storeName, style: t.headlineSmall),
        Text('${order.address}, ${order.comuna}'),
        const SizedBox(height: 4),
        Text('${order.bagTitle} · ${formatClp(order.amount)}'),
        const SizedBox(height: 16),
      ],
    );

    switch (order.status) {
      case OrderStatus.paid:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Text('Muestra este código en el local', style: t.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                // El QR contiene solo el código, así el comercio puede escanearlo o tipearlo.
                child: QrImageView(data: order.pickupCode, size: 220),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              order.pickupCode,
              textAlign: TextAlign.center,
              style: t.displaySmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(pickup, textAlign: TextAlign.center, style: t.titleMedium),
          ],
        );
      case OrderStatus.pendingPayment:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const Text('Tu bolsa está reservada por 15 minutos mientras completas el pago.'),
            const SizedBox(height: 16),
            if (order.checkoutUrl != null)
              FilledButton(
                onPressed: () => openCheckout(context, order.checkoutUrl!),
                child: const Text('Completar pago'),
              ),
          ],
        );
      case OrderStatus.pickedUp:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Icon(Icons.check_circle, size: 72, color: scheme.primary),
            const SizedBox(height: 8),
            Text('¡Retirado! Gracias por rescatar comida 🌱', textAlign: TextAlign.center, style: t.titleMedium),
          ],
        );
      case OrderStatus.cancelled:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Text('Este pedido fue cancelado (pago no completado).',
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => context.go('/'), child: const Text('Ver otras bolsas')),
          ],
        );
    }
  }
}
