import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

enum _Period {
  today('Hoy', 0),
  week('7 días', 6),
  month('30 días', 29);

  const _Period(this.label, this.daysBack);
  final String label;
  final int daysBack;

  DateTime get since {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  }
}

/// Métricas de ventas y últimos pedidos de toda la plataforma.
class SalesTab extends StatefulWidget {
  const SalesTab({super.key});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  _Period _period = _Period.today;
  late Stream<List<BagOrder>> _orders = Repository.instance.watchOrdersSince(_period.since);

  void _select(_Period p) => setState(() {
        _period = p;
        _orders = Repository.instance.watchOrdersSince(p.since);
      });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BagOrder>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final orders = snap.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: SegmentedButton<_Period>(
                segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
                selected: {_period},
                onSelectionChanged: (v) => _select(v.first),
              ),
            ),
            const SizedBox(height: 16),
            if (orders == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              _Kpis(orders: orders),
              const SizedBox(height: 24),
              Text('Pedidos', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (orders.isEmpty) const Text('Sin pedidos en este periodo.'),
              for (final o in orders)
                Card(
                  child: ListTile(
                    title: Text('${o.storeName} · ${o.bagTitle}'),
                    subtitle: Text(o.createdAt == null
                        ? o.status.label
                        : '${o.createdAt!.day}/${o.createdAt!.month} '
                            '${o.createdAt!.hour.toString().padLeft(2, '0')}:'
                            '${o.createdAt!.minute.toString().padLeft(2, '0')} · ${o.status.label}'),
                    trailing: Text(formatClp(o.amount)),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.orders});

  final List<BagOrder> orders;

  @override
  Widget build(BuildContext context) {
    final sold = orders.where((o) => o.status == OrderStatus.paid || o.status == OrderStatus.pickedUp).toList();
    final pickedUp = sold.where((o) => o.status == OrderStatus.pickedUp).length;
    final gmv = sold.fold<int>(0, (s, o) => s + o.amount);
    final fees = sold.fold<int>(0, (s, o) => s + o.platformFee);
    final cancelled = orders.where((o) => o.status == OrderStatus.cancelled).length;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Kpi(label: 'Bolsas vendidas', value: '${sold.length}'),
        _Kpi(label: 'Ventas totales', value: formatClp(gmv)),
        _Kpi(label: 'Comisión Woowfy', value: formatClp(fees), highlight: true),
        _Kpi(label: 'Retiradas', value: sold.isEmpty ? '–' : '${(pickedUp * 100 / sold.length).round()}%'),
        _Kpi(label: 'Canceladas', value: '$cancelled'),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 180,
      child: Card(
        color: highlight ? scheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
