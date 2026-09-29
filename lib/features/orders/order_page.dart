import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../bags/stars.dart';
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
        leading: BackButton(onPressed: () => context.go('/orders')),
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
    final pickup =
        'Retiro ${formatPickupWindow(order.pickupStart, order.pickupEnd)}';

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
        final deadline = order.cancelDeadline;
        final canCancel = DateTime.now().isBefore(deadline);
        final deadlineText =
            '${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Text(
              'Muestra este código en el local',
              style: t.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _PickupCode(order: order),
            const SizedBox(height: 8),
            Text(pickup, textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 24),
            if (canCancel) ...[
              Text(
                'Puedes cancelar con reembolso hasta las $deadlineText.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
              ),
              TextButton.icon(
                onPressed: () => _cancel(context, paid: true),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar pedido'),
                style: TextButton.styleFrom(foregroundColor: scheme.error),
              ),
            ] else
              Text(
                'Ya no se puede cancelar: el plazo es hasta $cancelHoursBefore horas antes del retiro '
                'o $cancelGraceMinutes minutos después de pagar.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
              ),
          ],
        );
      case OrderStatus.pendingPayment:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const Text(
              'Tu bolsa está reservada por 15 minutos mientras completas el pago.',
            ),
            const SizedBox(height: 16),
            if (order.checkoutUrl != null)
              FilledButton(
                onPressed: () => openCheckout(context, order.checkoutUrl!),
                child: const Text('Completar pago'),
              ),
            _VerifyPayment(orderId: order.id),
            TextButton(
              onPressed: () => _cancel(context, paid: false),
              child: const Text('Cancelar reserva'),
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
            Text(
              '¡Retirado! Gracias por rescatar comida',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
            const SizedBox(height: 24),
            order.rating == null
                ? _RateCard(orderId: order.id)
                : Column(
                    children: [
                      Stars(value: order.rating!.toDouble(), size: 28),
                      const SizedBox(height: 4),
                      Text(
                        'Gracias por calificar',
                        style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                      ),
                    ],
                  ),
          ],
        );
      case OrderStatus.noShow:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const Icon(Icons.schedule, size: 64, color: WoowfyColors.muted),
            const SizedBox(height: 8),
            Text(
              'No retiraste esta bolsa a tiempo',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'El horario de retiro era ${formatPickupWindow(order.pickupStart, order.pickupEnd)}. Como el local la apartó '
              'para ti, no hay reembolso. Si tuviste un problema, escríbenos a hola@woowfy.com.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: WoowfyColors.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Ver otras bolsas'),
            ),
          ],
        );
      case OrderStatus.cancelled:
        final (why, refundable) = switch (order.cancelReason) {
          'customer' => ('Cancelaste este pedido.', true),
          'store' => (
            'El local canceló la bolsa${order.storeMessage == null ? '.' : ': ${order.storeMessage}'}',
            true,
          ),
          'payment_timeout' => (
            'La reserva venció porque el pago no se completó a tiempo.',
            false,
          ),
          'payment_rejected' => ('El pago no fue aprobado.', false),
          _ => ('Este pedido fue cancelado.', false),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Text(why, style: t.titleMedium),
            if (refundable || order.refundStatus != null) ...[
              const SizedBox(height: 12),
              _RefundStatus(status: order.refundStatus, amount: order.amount),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.go('/'),
              child: const Text('Ver otras bolsas'),
            ),
          ],
        );
    }
  }

  Future<void> _cancel(BuildContext context, {required bool paid}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(paid ? 'Cancelar pedido' : 'Cancelar reserva'),
        content: Text(
          paid
              ? 'Te devolveremos ${formatClp(order.amount)} al mismo medio de pago. La bolsa quedará disponible para otra persona.'
              : 'La bolsa quedará disponible para otra persona.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final refunded = await Repository.instance.cancelOrder(order.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            refunded
                ? 'Pedido cancelado. Te devolvimos el dinero.'
                : 'Reserva cancelada.',
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'No se pudo cancelar.')),
      );
    }
  }
}

/// QR y código de retiro. El código está en un documento privado del cliente (el comercio no lo puede leer);
/// los pedidos antiguos lo traen en el mismo pedido.
class _PickupCode extends StatelessWidget {
  const _PickupCode({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<String?>(
      stream: Repository.instance.watchPickupCode(order.id),
      builder: (context, snap) {
        final code = snap.data ?? (order.pickupCode.isEmpty ? null : order.pickupCode);
        if (code == null) {
          return const SizedBox(height: 252, child: Center(child: CircularProgressIndicator()));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                // El QR contiene solo el código, así el comercio puede escanearlo o tipearlo.
                child: QrImageView(data: code, size: 220),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: t.displaySmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
            ),
          ],
        );
      },
    );
  }
}

/// Al abrir un pedido pendiente (p. ej. al volver de Mercado Pago) le pide al servidor que verifique el pago,
/// por si el aviso del webhook se atrasó. También ofrece reintentarlo a mano.
class _VerifyPayment extends StatefulWidget {
  const _VerifyPayment({required this.orderId});

  final String orderId;

  @override
  State<_VerifyPayment> createState() => _VerifyPaymentState();
}

class _VerifyPaymentState extends State<_VerifyPayment> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _verify(silent: true);
  }

  Future<void> _verify({bool silent = false}) async {
    setState(() => _busy = true);
    try {
      final paid = await Repository.instance.syncOrderPayment(widget.orderId);
      // Si quedó pagado, el StreamBuilder del pedido cambia solo a la pantalla del QR.
      if (!paid && !silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Aún no vemos tu pago. Si ya pagaste, espera unos segundos y vuelve a intentarlo.'),
        ));
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No pudimos verificar el pago. Intenta de nuevo.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : () => _verify(),
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh, size: 18),
      label: Text(_busy ? 'Verificando pago…' : 'Ya pagué, verificar'),
    );
  }
}

class _RefundStatus extends StatelessWidget {
  const _RefundStatus({required this.status, required this.amount});

  final String? status;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final (icon, text, bg) = switch (status) {
      'done' => (
        Icons.check_circle_outline,
        'Reembolso de ${formatClp(amount)} realizado. Puede tardar unos días en verse en tu medio de pago.',
        WoowfyColors.limeSoft,
      ),
      'error' => (
        Icons.error_outline,
        'No pudimos procesar el reembolso automáticamente. Te contactaremos; escríbenos a hola@woowfy.com.',
        const Color(0xFFFFE0D9),
      ),
      _ => (
        Icons.schedule,
        'Reembolso de ${formatClp(amount)} en proceso.',
        WoowfyColors.orangeSoft,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: WoowfyColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Calificar un pedido retirado: estrellas y comentario opcional.
class _RateCard extends StatefulWidget {
  const _RateCard({required this.orderId});

  final String orderId;

  @override
  State<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<_RateCard> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repository.instance.rateOrder(
        widget.orderId,
        _rating,
        _comment.text.trim(),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('¡Gracias! Tu calificación ayuda a otros a elegir.'),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'No se pudo enviar.')),
      );
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('¿Cómo estuvo tu bolsa?', style: t.titleMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i de 5',
                    iconSize: 36,
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: WoowfyColors.orange,
                    ),
                  ),
              ],
            ),
            if (_rating > 0) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _comment,
                maxLines: 2,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Cuéntanos más (opcional)',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(_sending ? 'Enviando…' : 'Enviar calificación'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
