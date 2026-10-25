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
        const _NeedsAttention(),
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

/// Dinero de clientes que no se pudo devolver solo (reembolso fallido o pago que no calzaba). Solo aparece si hay algo.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention();

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return StreamBuilder<List<BagOrder>>(
      stream: repo.watchFailedRefunds(),
      builder: (context, refunds) => StreamBuilder<List<BagOrder>>(
        stream: repo.watchFailedPaymentIssues(),
        builder: (context, issues) {
          if (refunds.hasError || issues.hasError) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text('No pudimos revisar si hay reembolsos fallidos.', style: TextStyle(color: WoowfyColors.muted)),
            );
          }
          final byId = {for (final o in [...?refunds.data, ...?issues.data]) o.id: o};
          if (byId.isEmpty) return const SizedBox.shrink();
          final t = Theme.of(context).textTheme;
          final error = Theme.of(context).colorScheme.error;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Card(
              color: WoowfyColors.orangeSoft,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: error)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.error_outline, color: error),
                    const SizedBox(width: 8),
                    Text('Requiere atención', style: t.titleMedium?.copyWith(color: error)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Mercado Pago no aceptó estas devoluciones. Reintenta; si vuelve a fallar, devuélvelo desde el panel '
                    'de Mercado Pago con el número de pedido.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final o in byId.values) _AttentionRow(order: o),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AttentionRow extends StatefulWidget {
  const _AttentionRow({required this.order});

  final BagOrder order;

  @override
  State<_AttentionRow> createState() => _AttentionRowState();
}

class _AttentionRowState extends State<_AttentionRow> {
  bool _busy = false;

  Future<void> _retry() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final ok = await Repository.instance.retryRefund(widget.order.id);
      messenger.showSnackBar(SnackBar(
        content: Text(ok ? 'Listo: el dinero se devolvió.' : 'Mercado Pago volvió a rechazarlo. Revisa el motivo.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo reintentar. Intenta de nuevo.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final mismatch = o.paymentIssueStatus == 'error';
    final what = mismatch
        ? 'Pago de ${formatClp(o.paymentIssueAmount ?? 0)} que no calzaba con el pedido (${formatClp(o.amount)})'
        : 'Reembolso de ${formatClp(o.amount)}';
    final why = mismatch ? o.paymentIssueError : o.refundError;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${o.storeName} · ${o.bagTitle}'),
      subtitle: Text([what, 'Pedido ${o.id}', if (why != null && why.isNotEmpty) why].join('\n')),
      isThreeLine: true,
      trailing: FilledButton.tonal(
        onPressed: _busy ? null : _retry,
        child: Text(_busy ? 'Reintentando…' : 'Reintentar'),
      ),
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

  /// Planilla de una liquidación ya registrada, con la cuenta a la que se pagó (guardada al liquidar). Las
  /// liquidaciones antiguas no la guardaron: se usa la cuenta actual del local y se avisa.
  Future<void> _copy(BuildContext context, Payout p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bank = p.destination ?? await Repository.instance.getBankAccount(p.storeId);
      String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final csv = [
        'local,titular,rut,banco,tipo_cuenta,numero_cuenta,correo,monto,ventas,liquidacion',
        [p.storeName, bank?.holder, bank?.rut, bank?.bank, bank?.accountTypeLabel, bank?.accountNumber, bank?.email,
                p.storeAmount, p.orderCount, p.id]
            .map(cell)
            .join(','),
      ].join('\n');
      await Clipboard.setData(ClipboardData(text: csv));
      messenger.showSnackBar(SnackBar(
        content: Text(p.destination != null
            ? 'Planilla copiada (CSV).'
            : 'Planilla copiada con la cuenta actual del local: esta liquidación es anterior y no guardó la cuenta de destino.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo copiar la planilla.'))));
    }
  }

  /// Anular: solo si la transferencia no se hizo. Las ventas vuelven a "por pagar".
  Future<void> _void(BuildContext context, Payout p) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anular liquidación'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.storeName} · ${formatClp(p.storeAmount)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Sus ${p.orderCount} ${p.orderCount == 1 ? 'venta vuelve' : 'ventas vuelven'} a "por pagar" y el local deja de '
                'verla como pago recibido. Anula solo si no transferiste.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Motivo', hintText: 'La transferencia fue rechazada.'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await Repository.instance.voidPayout(p.id, text);
      messenger.showSnackBar(SnackBar(content: Text('Liquidación anulada: $n ${n == 1 ? 'venta volvió' : 'ventas volvieron'} a "por pagar".')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo anular. Intenta de nuevo.'))));
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
                  leading: Icon(p.voided ? Icons.block : Icons.account_balance_outlined,
                      color: p.voided ? WoowfyColors.muted : WoowfyColors.green),
                  title: Text(
                    '${p.storeName} · ${formatClp(p.storeAmount)}',
                    style: p.voided ? const TextStyle(decoration: TextDecoration.lineThrough, color: WoowfyColors.muted) : null,
                  ),
                  subtitle: Text([
                    if (p.voided) 'Anulada${p.voidReason.isEmpty ? '' : ': ${p.voidReason}'}',
                    if (p.createdAt != null) _date.format(p.createdAt!),
                    '${p.orderCount} ${p.orderCount == 1 ? 'venta' : 'ventas'}',
                    if (p.note.isNotEmpty) p.note,
                  ].join(' · ')),
                  trailing: p.voided
                      ? null
                      : PopupMenuButton<String>(
                          tooltip: 'Opciones de la liquidación',
                          onSelected: (v) => v == 'copy' ? _copy(context, p) : _void(context, p),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'copy',
                              child: ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Copiar planilla')),
                            ),
                            PopupMenuItem(
                              value: 'void',
                              child: ListTile(leading: Icon(Icons.block), title: Text('Anular')),
                            ),
                          ],
                        ),
                ),
              ),
            ),
        ]);
      },
    ));
  }
}
