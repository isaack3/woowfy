import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'stores_tabs.dart' show PayAllBar, PayoutDialog;

final _date = DateFormat('d MMM y, HH:mm', 'es_CL');

/// Lo único del admin que mueve plata, en un solo lugar: lo que se debe a cada local y lo ya pagado.
class PayoutsTab extends StatelessWidget {
  const PayoutsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PayAllBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Por local', style: t.titleMedium),
        ),
        const _PendingByStore(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('Historial de liquidaciones', style: t.titleMedium),
        ),
        const _History(),
      ],
    );
  }
}

class _PendingByStore extends StatelessWidget {
  const _PendingByStore();

  @override
  Widget build(BuildContext context) {
    return Reloadable(builder: (context) => StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchAllUnpaidOrders(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar lo que hay por pagar', error: snap.error);
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final byStore = <String, List<BagOrder>>{};
        for (final o in snap.data!) {
          byStore.putIfAbsent(o.storeId, () => []).add(o);
        }
        if (byStore.isEmpty) {
          return const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Todo liquidado.'));
        }
        final entries = byStore.entries.toList()
          ..sort((a, b) => b.value.fold<int>(0, (s, o) => s + o.storeAmount).compareTo(a.value.fold<int>(0, (s, o) => s + o.storeAmount)));
        return Column(children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.storefront_outlined, color: WoowfyColors.green),
                  title: Text(e.value.first.storeName),
                  subtitle: Text('${e.value.length} ${e.value.length == 1 ? 'venta' : 'ventas'} sin liquidar'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(formatClp(e.value.fold<int>(0, (s, o) => s + o.storeAmount)),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => PayoutDialog(storeId: e.key, storeName: e.value.first.storeName),
                      ),
                      child: const Text('Liquidar'),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
      },
    ));
  }
}

class _History extends StatelessWidget {
  const _History();

  /// Planilla de una liquidación ya registrada, con los datos bancarios actuales del local.
  Future<void> _copy(BuildContext context, Payout p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bank = await Repository.instance.getBankAccount(p.storeId);
      String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final csv = [
        'local,titular,rut,banco,tipo_cuenta,numero_cuenta,correo,monto,ventas,liquidacion',
        [p.storeName, bank?.holder, bank?.rut, bank?.bank, bank?.accountTypeLabel, bank?.accountNumber, bank?.email,
                p.storeAmount, p.orderCount, p.id]
            .map(cell)
            .join(','),
      ].join('\n');
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(const SnackBar(content: Text('Planilla copiada (CSV).')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo copiar la planilla.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted);
    return Reloadable(builder: (context) => StreamBuilder<List<Payout>>(
      stream: Repository.instance.watchAllPayouts(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar el historial', error: snap.error);
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        final payouts = snap.data!;
        if (payouts.isEmpty) {
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Aún no hay liquidaciones.', style: muted));
        }
        return Column(children: [
          for (final p in payouts)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined, color: WoowfyColors.green),
                  title: Text('${p.storeName} · ${formatClp(p.storeAmount)}'),
                  subtitle: Text([
                    if (p.createdAt != null) _date.format(p.createdAt!),
                    '${p.orderCount} ${p.orderCount == 1 ? 'venta' : 'ventas'}',
                    if (p.note.isNotEmpty) p.note,
                  ].join(' · ')),
                  trailing: TextButton.icon(
                    onPressed: () => _copy(context, p),
                    icon: const Icon(Icons.table_view_outlined, size: 18),
                    label: const Text('Copiar planilla'),
                  ),
                ),
              ),
            ),
        ]);
      },
    ));
  }
}
