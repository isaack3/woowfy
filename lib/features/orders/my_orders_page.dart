import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_image.dart';
import '../shell/app_shell.dart';

class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(title: const WoowfyLogo(onDark: true)),
      body: StreamBuilder<List<BagOrder>>(
        stream: Repository.instance.watchMyOrders(uid),
        builder: (context, snap) {
          final orders = snap.data;
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              const GreenHeader(title: 'Mis pedidos', subtitle: 'Muestra el QR en el local para retirar'),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: snap.hasError
                        ? Text('No pudimos cargar tus pedidos: ${snap.error}')
                        : orders == null
                            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                            : orders.isEmpty
                                ? _Empty()
                                : Column(children: [
                                    for (final o in orders)
                                      Padding(padding: const EdgeInsets.only(bottom: 10), child: _OrderTile(order: o)),
                                  ]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final BagOrder order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    return Card(
      child: InkWell(
        onTap: () => context.go('/order/${o.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(width: 64, height: 64, child: BagImage(url: o.imageUrl, iconSize: 24)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.storeName, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(o.bagTitle, style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                    const SizedBox(height: 2),
                    Text(
                      '${o.pickupStart.day}/${o.pickupStart.month} · ${formatPickupWindow(o.pickupStart, o.pickupEnd)} · ${formatClp(o.amount)}',
                      style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                    ),
                  ],
                ),
              ),
              o.status == OrderStatus.pickedUp && o.rating == null
                  ? const _RatePill()
                  : OrderStatusPill(o.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estado del pedido con el color de la marca.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      OrderStatus.paid => (WoowfyColors.lime, WoowfyColors.green),
      OrderStatus.pendingPayment => (WoowfyColors.orangeSoft, const Color(0xFF7A3510)),
      OrderStatus.pickedUp => (const Color(0xFFEDEAE0), WoowfyColors.muted),
      OrderStatus.cancelled => (const Color(0xFFFFE0D9), const Color(0xFFB83A22)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
      child: Text(status.label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Image.asset('assets/brand/woowfy-isotipo.png', height: 64),
            const SizedBox(height: 12),
            const Text('Aún no tienes pedidos. Rescata tu primera bolsa.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Ver bolsas')),
          ],
        ),
      ),
    );
  }
}

class _RatePill extends StatelessWidget {
  const _RatePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: const ShapeDecoration(color: WoowfyColors.orangeSoft, shape: StadiumBorder()),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.star_rounded, size: 14, color: WoowfyColors.orange),
        SizedBox(width: 4),
        Text('Califica', style: TextStyle(color: Color(0xFF7A3510), fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}
