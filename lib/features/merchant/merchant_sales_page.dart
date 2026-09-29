import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/stars.dart';

final _date = DateFormat('d MMM y', 'es_CL');

enum _Period {
  week('7 días', 6),
  month('30 días', 29),
  quarter('90 días', 89);

  const _Period(this.label, this.daysBack);
  final String label;
  final int daysBack;

  DateTime get since {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).subtract(Duration(days: daysBack));
  }
}

/// Ventas y pagos del comercio: lo vendido, la comisión, lo que Woowfy le pagó y lo pendiente, y sus opiniones.
class MerchantSalesPage extends StatelessWidget {
  const MerchantSalesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas y pagos'),
        leading: BackButton(onPressed: () => context.go('/merchant')),
      ),
      body: StreamBuilder<Store?>(
        stream: Repository.instance.watchMyStore(uid),
        builder: (context, snap) {
          final store = snap.data;
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (store == null || !store.approved) return const Center(child: Text('Tu local aún no está activo.'));
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Pending(storeId: store.id),
                  const SizedBox(height: 16),
                  _Sales(storeId: store.id),
                  const SizedBox(height: 24),
                  _Payouts(storeId: store.id),
                  const SizedBox(height: 24),
                  _StoreReviews(store: store),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Saldo por cobrar: pedidos retirados que Woowfy aún no le paga.
class _Pending extends StatelessWidget {
  const _Pending({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchUnpaidPickedUp(storeId),
      builder: (context, snap) {
        final orders = snap.data ?? const <BagOrder>[];
        final amount = orders.fold<int>(0, (s, o) => s + o.storeAmount);
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: WoowfyColors.green, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Por recibir', style: t.titleMedium?.copyWith(color: WoowfyColors.lime)),
            const SizedBox(height: 4),
            Text(formatClp(amount), style: t.headlineLarge?.copyWith(color: WoowfyColors.cream)),
            const SizedBox(height: 4),
            Text(
              orders.isEmpty
                  ? 'No tienes ventas pendientes de pago.'
                  : '${orders.length} ${orders.length == 1 ? 'bolsa retirada' : 'bolsas retiradas'} aún sin liquidar (ya descontada la comisión).',
              style: t.bodySmall?.copyWith(color: WoowfyColors.cream),
            ),
          ]),
        );
      },
    );
  }
}

class _Sales extends StatefulWidget {
  const _Sales({required this.storeId});

  final String storeId;

  @override
  State<_Sales> createState() => _SalesState();
}

class _SalesState extends State<_Sales> {
  _Period _period = _Period.month;
  late Stream<List<BagOrder>> _orders = Repository.instance.watchStoreOrdersSince(widget.storeId, _period.since);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagOrder>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.hasError) return Text('No pudimos cargar las ventas: ${snap.error}');
        final orders = snap.data;
        final sold = (orders ?? const <BagOrder>[])
            .where((o) => o.status == OrderStatus.paid || o.status == OrderStatus.pickedUp)
            .toList();
        final cancelled = (orders ?? const <BagOrder>[]).where((o) => o.status == OrderStatus.cancelled && o.refundStatus != null).length;
        final gross = sold.fold<int>(0, (s, o) => s + o.amount);
        final fee = sold.fold<int>(0, (s, o) => s + o.platformFee);
        Widget kpi(String label, String value, {bool strong = false}) => Expanded(
              child: Card(
                color: strong ? WoowfyColors.limeSoft : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: t.bodySmall),
                    const SizedBox(height: 4),
                    Text(value, style: t.titleLarge),
                  ]),
                ),
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Ventas', style: t.titleMedium)),
              SegmentedButton<_Period>(
                segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _period = v.first;
                  _orders = Repository.instance.watchStoreOrdersSince(widget.storeId, _period.since);
                }),
              ),
            ]),
            const SizedBox(height: 8),
            if (orders == null)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else ...[
              Row(children: [kpi('Bolsas vendidas', '${sold.length}'), kpi('Ventas', formatClp(gross))]),
              Row(children: [
                kpi('Comisión Woowfy', formatClp(fee)),
                kpi('Para ti', formatClp(gross - fee), strong: true),
              ]),
              if (cancelled > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$cancelled ${cancelled == 1 ? 'pedido cancelado y reembolsado' : 'pedidos cancelados y reembolsados'} en el periodo.',
                      style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Payouts extends StatelessWidget {
  const _Payouts({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Payout>>(
      stream: Repository.instance.watchPayouts(storeId),
      builder: (context, snap) {
        final payouts = snap.data ?? const <Payout>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pagos recibidos', style: t.titleMedium),
            const SizedBox(height: 8),
            if (payouts.isEmpty) Text('Aún no hay pagos registrados.', style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
            for (final p in payouts)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined, color: WoowfyColors.green),
                  title: Text(formatClp(p.storeAmount)),
                  subtitle: Text([
                    if (p.createdAt != null) _date.format(p.createdAt!),
                    '${p.orderCount} ${p.orderCount == 1 ? 'bolsa' : 'bolsas'}',
                    'ventas ${formatClp(p.grossAmount)} − comisión ${formatClp(p.platformFee)}',
                    if (p.note.isNotEmpty) p.note,
                  ].join(' · ')),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StoreReviews extends StatelessWidget {
  const _StoreReviews({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Review>>(
      stream: Repository.instance.watchStoreReviews(store.id, limit: 30),
      builder: (context, snap) {
        final reviews = snap.data ?? const <Review>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Opiniones', style: t.titleMedium)),
              if (store.ratingAvg != null) ...[
                Stars(value: store.ratingAvg!),
                const SizedBox(width: 6),
                Text('${formatRating(store.ratingAvg!)} (${store.ratingCount})', style: t.labelLarge),
              ],
            ]),
            const SizedBox(height: 8),
            if (reviews.isEmpty) Text('Todavía no tienes calificaciones.', style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
            for (final r in reviews)
              Card(
                child: ListTile(
                  title: Row(children: [
                    Stars(value: r.rating.toDouble(), size: 14),
                    const SizedBox(width: 8),
                    Text(r.userName, style: t.labelLarge),
                  ]),
                  subtitle: Text([
                    r.bagTitle,
                    if (r.createdAt != null) _date.format(r.createdAt!),
                    if (r.comment.isNotEmpty) '"${r.comment}"',
                  ].join(' · ')),
                ),
              ),
          ],
        );
      },
    );
  }
}
