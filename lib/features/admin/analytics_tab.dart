import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
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

/// Analítica básica: visitas (contadores anónimos de stats/) y el embudo hasta la compra (datos reales).
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  _Period _period = _Period.week;
  late Stream<List<DayStats>> _stats;
  late Stream<List<BagOrder>> _orders;
  late Future<(int, int)> _signups;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final since = _period.since;
    _stats = Repository.instance.watchStatsSince(since);
    _orders = Repository.instance.watchOrdersSince(since);
    _signups = (
      Repository.instance.countCreatedSince('waitlist', since),
      Repository.instance.countCreatedSince('users', since),
    ).wait;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<DayStats>>(
      stream: _stats,
      builder: (context, statsSnap) => StreamBuilder<List<BagOrder>>(
        stream: _orders,
        builder: (context, ordersSnap) {
          if (statsSnap.hasError || ordersSnap.hasError) {
            return Center(child: Text('No pudimos cargar la analítica: ${statsSnap.error ?? ordersSnap.error}'));
          }
          final days = statsSnap.data;
          final orders = ordersSnap.data;
          int sum(String e) => (days ?? const <DayStats>[]).fold(0, (s, d) => s + d[e]);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: SegmentedButton<_Period>(
                  segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
                  selected: {_period},
                  onSelectionChanged: (v) => setState(() {
                    _period = v.first;
                    _load();
                  }),
                ),
              ),
              const SizedBox(height: 16),
              if (days == null || orders == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Kpi(label: 'Visitas a woowfy.com', value: sum('landing_visit'), caption: '${sum('landing_view')} páginas vistas'),
                    _Kpi(label: 'Guía para comercios', value: sum('guide_view'), caption: 'veces abierta'),
                    _Kpi(label: 'Visitas a la app', value: sum('app_visit'), caption: 'sesiones', highlight: true),
                    FutureBuilder<(int, int)>(
                      future: _signups,
                      builder: (context, s) => _Kpi(
                        label: 'Lista de espera',
                        value: s.data?.$1,
                        caption: s.data == null ? '' : '${s.data!.$2} cuentas nuevas en la app',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Visitas por día', style: t.titleMedium),
                const SizedBox(height: 8),
                _DailyBars(days: days, since: _period.since),
                const SizedBox(height: 24),
                Text('Camino a la compra', style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Cada paso muestra cuántos llegan y qué porcentaje del paso anterior.',
                  style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                ),
                const SizedBox(height: 8),
                _Funnel(steps: [
                  ('Visitas a la app', sum('app_visit')),
                  ('Vieron una bolsa', sum('bag_view')),
                  ('Tocaron "Reservar"', sum('checkout_start')),
                  ('Reservas creadas', orders.length),
                  ('Pagadas', orders.where((o) => o.status.isSold).length),
                  ('Retiradas', orders.where((o) => o.status == OrderStatus.pickedUp).length),
                ]),
                const SizedBox(height: 12),
                Text(
                  'Las visitas se cuentan sin cookies ni datos personales (una por sesión del navegador). '
                  'Las reservas, pagos y retiros salen de los pedidos reales.',
                  style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.caption = '', this.highlight = false});

  final String label;
  final int? value;
  final String caption;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 200,
      child: Card(
        color: highlight ? WoowfyColors.limeSoft : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: t.bodySmall),
              const SizedBox(height: 6),
              Text(value?.toString() ?? '…', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              if (caption.isNotEmpty) Text(caption, style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barras simples por día: visitas a woowfy.com (verde) y a la app (lima).
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days, required this.since});

  final List<DayStats> days;
  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String two(int n) => n.toString().padLeft(2, '0');
    final byDay = {for (final d in days) d.day: d};
    final today = DateTime.now();
    final dates = [
      for (var d = since; !d.isAfter(DateTime(today.year, today.month, today.day)); d = d.add(const Duration(days: 1))) d,
    ];
    final values = [
      for (final d in dates)
        (d, byDay['${d.year}-${two(d.month)}-${two(d.day)}']?['landing_visit'] ?? 0,
            byDay['${d.year}-${two(d.month)}-${two(d.day)}']?['app_visit'] ?? 0),
    ];
    final maxValue = math.max(1, values.fold<int>(0, (m, v) => math.max(m, math.max(v.$2, v.$3))));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in values)
                    Expanded(
                      child: Tooltip(
                        message: '${v.$1.day}/${v.$1.month}: ${v.$2} en woowfy.com · ${v.$3} en la app',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _bar(v.$2 / maxValue, WoowfyColors.green),
                              const SizedBox(width: 2),
                              _bar(v.$3 / maxValue, WoowfyColors.lime),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${values.first.$1.day}/${values.first.$1.month}', style: t.bodySmall),
                Text('Hoy', style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 16, children: [
              _legend('woowfy.com', WoowfyColors.green, t),
              _legend('App', WoowfyColors.lime, t),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _bar(double fraction, Color color) => Expanded(
        child: FractionallySizedBox(
          heightFactor: math.max(fraction, 0.02),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          ),
        ),
      );

  Widget _legend(String label, Color color, TextTheme t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: t.bodySmall),
      ]);
}

/// Embudo: cuántos llegan a cada paso y el porcentaje respecto del paso anterior.
class _Funnel extends StatelessWidget {
  const _Funnel({required this.steps});

  final List<(String, int)> steps;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = math.max(1, steps.first.$2);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                children: [
                  SizedBox(width: 170, child: Text(steps[i].$1)),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: math.min(1, steps[i].$2 / top),
                        minHeight: 14,
                        color: i >= 4 ? WoowfyColors.green : WoowfyColors.lime,
                        backgroundColor: WoowfyColors.cream,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      i == 0 || steps[i - 1].$2 == 0
                          ? '${steps[i].$2}'
                          : '${steps[i].$2} · ${(steps[i].$2 * 100 / steps[i - 1].$2).round()}%',
                      textAlign: TextAlign.right,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (i < steps.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
