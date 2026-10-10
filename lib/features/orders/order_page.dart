import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/checkout.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../bags/stars.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'countdown.dart';

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
      body: Reloadable(builder: (context) => StreamBuilder<BagOrder?>(
        stream: Repository.instance.watchOrder(orderId),
        builder: (context, snap) {
          if (snap.hasError) {
            return _SavedOr(
              orderId: orderId,
              offline: true,
              orElse: ErrorRetry(title: 'No pudimos cargar el pedido', error: snap.error),
            );
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return _SavedOr(orderId: orderId, orElse: const Center(child: CircularProgressIndicator()));
          }
          final order = snap.data;
          if (order == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('No encontramos este pedido.', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => context.go('/orders'), child: const Text('Ver mis pedidos')),
                ]),
              ),
            );
          }
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
      )),
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
        'Retiro ${formatPickup(order.pickupStart, order.pickupEnd, withDate: true)}';

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.storeName, style: t.headlineSmall),
        Text([order.address, order.comuna].where((s) => s.isNotEmpty).join(', ')),
        const SizedBox(height: 4),
        Text('${order.bagTitle} · ${formatClp(order.amount)}'),
        const SizedBox(height: 16),
      ],
    );

    switch (order.status) {
      case OrderStatus.paid:
        final deadline = order.cancelDeadline;
        final canCancel = DateTime.now().isBefore(deadline);
        final deadlineText = '${formatPickupDay(deadline)} a las ${formatTime(deadline)}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.paidAt != null && DateTime.now().difference(order.paidAt!).inMinutes < 30) ...[
              _JustPaid(order: order),
              const SizedBox(height: 16),
            ],
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
            _HowToGet(order: order),
            const SizedBox(height: 16),
            if (canCancel) ...[
              Text(
                'Puedes cancelar con reembolso hasta $deadlineText.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
              ),
              const SizedBox(height: 32),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text('Más opciones', style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextButton.icon(
                      onPressed: () => _cancel(context, paid: true),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancelar pedido'),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                    ),
                  ],
                ),
              ),
            ] else
              Text(
                'Ya no se puede cancelar: el plazo es hasta $cancelHoursBefore horas antes del retiro '
                'o $cancelGraceMinutes minutos después de pagar.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
              ),
            const SizedBox(height: 16),
            _PickupHelp(order: order),
          ],
        );
      case OrderStatus.pendingPayment:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            _VerifyPayment(orderId: order.id),
            const SizedBox(height: 12),
            if (order.expiresAt != null)
              Countdown(
                until: order.expiresAt!,
                builder: (context, left) => Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    Text(left == Duration.zero ? 'La reserva venció' : 'Te la guardamos por',
                        style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
                    if (left > Duration.zero)
                      Text(formatMmSs(left),
                          style: t.headlineMedium?.copyWith(
                              color: WoowfyColors.green, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
              )
            else
              const Text('Tu bolsa está reservada por $paymentTimeoutMinutes minutos mientras completas el pago.'),
            const SizedBox(height: 16),
            if (order.checkoutUrl != null)
              FilledButton(
                onPressed: () => openCheckout(context, order.checkoutUrl!),
                child: Text('Completar pago ${formatClp(order.amount)}'),
              ),
            const SizedBox(height: 16),
            const Divider(),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _cancel(context, paid: false),
                  style: TextButton.styleFrom(foregroundColor: WoowfyColors.muted),
                  child: const Text('Cancelar reserva'),
                ),
                TextButton(
                  onPressed: () => _writeUs(order),
                  child: const Text('¿Problemas? Escríbenos'),
                ),
              ],
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
              'para ti, no hay reembolso. Si tuviste un problema, escríbenos a hola@passva.com.',
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
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo cancelar. Intenta de nuevo.'))),
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
        _SavedReceipt.save(order, code);
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

/// Lo mínimo para retirar sin internet: se guarda en el teléfono cada vez que se ve el código de un pedido pagado.
class _SavedReceipt {
  const _SavedReceipt({required this.storeName, required this.bagTitle, required this.pickup, required this.code});

  final String storeName;
  final String bagTitle;
  final String pickup;
  final String code;

  static String _key(String orderId) => 'receipt.$orderId';

  static Future<void> save(BagOrder order, String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(order.id),
        jsonEncode({
          'storeName': order.storeName,
          'bagTitle': order.bagTitle,
          'pickup': formatPickup(order.pickupStart, order.pickupEnd, withDate: true),
          'code': code,
        }),
      );
    } catch (_) {}
  }

  static Future<_SavedReceipt?> load(String orderId) async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key(orderId));
      if (raw == null) return null;
      final d = jsonDecode(raw) as Map<String, dynamic>;
      return _SavedReceipt(
        storeName: d['storeName'] as String,
        bagTitle: d['bagTitle'] as String,
        pickup: d['pickup'] as String,
        code: d['code'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Mientras el pedido carga (o si no hay señal), muestra el código guardado; si no hay nada guardado, [orElse].
class _SavedOr extends StatelessWidget {
  const _SavedOr({required this.orderId, required this.orElse, this.offline = false});

  final String orderId;
  final Widget orElse;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<_SavedReceipt?>(
      future: _SavedReceipt.load(orderId),
      builder: (context, snap) {
        final r = snap.data;
        if (r == null) return orElse;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(24), children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(offline ? Icons.wifi_off : Icons.sync, size: 18, color: const Color(0xFF7A3510)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      offline ? 'Sin conexión: este es tu código guardado' : 'Actualizando… este es tu código guardado',
                      style: t.bodySmall?.copyWith(color: const Color(0xFF7A3510), fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text(r.storeName, style: t.headlineSmall),
              Text(r.bagTitle, style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(data: r.code, size: 220),
                ),
              ),
              const SizedBox(height: 16),
              Text(r.code,
                  textAlign: TextAlign.center,
                  style: t.displaySmall?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Retiro ${r.pickup}', textAlign: TextAlign.center, style: t.titleMedium),
              if (offline) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: Reloadable.retryOf(context),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                ),
              ],
            ]),
          ),
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
  int _autoChecks = 0;
  Timer? _timer;

  /// Al volver de Mercado Pago el aviso del pago puede atrasarse: se revisa solo cada 15 s durante 1 minuto.
  static const _maxAutoChecks = 4;

  @override
  void initState() {
    super.initState();
    _verify(silent: true);
    _timer = Timer.periodic(const Duration(seconds: 15), (t) {
      if (++_autoChecks >= _maxAutoChecks) t.cancel();
      if (mounted) _verify(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
    final t = Theme.of(context).textTheme;
    final checking = _busy || (_timer?.isActive ?? false);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: WoowfyColors.limeSoft, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (checking) ...[
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(checking ? 'Confirmando tu pago…' : '¿Ya pagaste?',
                style: t.titleSmall, textAlign: TextAlign.center),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          checking
              ? 'Si ya pagaste en Mercado Pago, puede tardar hasta 1 minuto. Lo revisamos solos.'
              : 'Si pagaste y aún no aparece, revísalo de nuevo o escríbenos.',
          style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
          textAlign: TextAlign.center,
        ),
        if (!checking)
          TextButton.icon(
            onPressed: () => _verify(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Revisar de nuevo'),
          ),
      ]),
    );
  }
}

/// Los primeros minutos después de pagar: el momento "es tuya", con lo pagado y lo ahorrado.
class _JustPaid extends StatelessWidget {
  const _JustPaid({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final saved = order.originalPrice == null ? null : order.originalPrice! - order.amount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: WoowfyColors.green, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Text('¡Es tuya!', style: t.headlineSmall?.copyWith(color: WoowfyColors.cream)),
        const SizedBox(height: 2),
        Text(
          saved != null && saved > 0
              ? 'Pagaste ${formatClp(order.amount)} · ahorraste ${formatClp(saved)}'
              : 'Pagaste ${formatClp(order.amount)}',
          style: t.titleSmall?.copyWith(color: WoowfyColors.lime),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text('Muestra este código en el local al retirar.',
            style: t.bodySmall?.copyWith(color: WoowfyColors.cream), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// La dirección del local abre el mapa ("Cómo llegar").
class _HowToGet extends StatelessWidget {
  const _HowToGet({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final place = [order.address, order.comuna].where((s) => s.isNotEmpty).join(', ');
    if (place.isEmpty) return const SizedBox.shrink();
    return Center(
      child: TextButton.icon(
        onPressed: () => launchUrl(Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${order.storeName}, $place, Chile')}')),
        icon: const Icon(Icons.place_outlined, size: 18),
        label: Text('$place · Cómo llegar'),
      ),
    );
  }
}

/// Si algo sale mal en el local: contacto con el código del pedido ya escrito.
class _PickupHelp extends StatelessWidget {
  const _PickupHelp({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.support_agent, color: WoowfyColors.green),
        title: const Text('¿Problemas con tu retiro?'),
        subtitle: Text('Escríbenos a $supportEmail con tu pedido', style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
        trailing: const Icon(Icons.mail_outline),
        onTap: () => _writeUs(order),
      ),
    );
  }
}

const supportEmail = 'hola@passva.com';

/// Abre el correo con el pedido ya identificado (asunto y cuerpo).
Future<void> _writeUs(BagOrder order) => launchUrl(Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=${Uri.encodeComponent('Pedido ${order.id} · ${order.storeName}')}'
          '&body=${Uri.encodeComponent('Hola, tengo un problema con mi pedido ${order.id} (${order.bagTitle}, ${order.storeName}).\n\n')}',
    ));

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
        'No pudimos procesar el reembolso automáticamente. Te contactaremos; escríbenos a hola@passva.com.',
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
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo enviar. Intenta de nuevo.'))),
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
