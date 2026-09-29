import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

final _date = DateFormat('d MMM y, HH:mm', 'es_CL');

/// Solicitudes de alta por revisar.
class PendingStoresTab extends StatelessWidget {
  const PendingStoresTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _StoreList(
      status: StoreStatus.pending,
      empty: 'No hay solicitudes pendientes 🎉',
      actions: (store) => [
        OutlinedButton(
          onPressed: () => _changeStatus(context, store, StoreStatus.rejected,
              askReason: 'Motivo del rechazo (lo verá el comercio)'),
          child: const Text('Rechazar'),
        ),
        FilledButton(
          onPressed: () => _changeStatus(context, store, StoreStatus.approved),
          child: const Text('Aprobar'),
        ),
      ],
    );
  }
}

/// Comercios ya revisados: activos, suspendidos o rechazados.
class StoresTab extends StatefulWidget {
  const StoresTab({super.key});

  @override
  State<StoresTab> createState() => _StoresTabState();
}

class _StoresTabState extends State<StoresTab> {
  StoreStatus _filter = StoreStatus.approved;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _PayAllBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<StoreStatus>(
            segments: [
              for (final s in [StoreStatus.approved, StoreStatus.suspended, StoreStatus.rejected])
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
        ),
        Expanded(
          child: _StoreList(
            key: ValueKey(_filter),
            status: _filter,
            empty: 'No hay comercios en este estado.',
            actions: (store) => switch (store.status) {
              StoreStatus.approved => [
                  FilledButton.tonal(
                    onPressed: () => showDialog<void>(context: context, builder: (_) => _PayoutDialog(store: store)),
                    child: const Text('Liquidar'),
                  ),
                  OutlinedButton(
                    onPressed: () => _changeStatus(context, store, StoreStatus.suspended,
                        askReason: 'Motivo de la suspensión (lo verá el comercio)'),
                    child: const Text('Suspender'),
                  ),
                ],
              _ => [
                  FilledButton.tonal(
                    onPressed: () => _changeStatus(context, store, StoreStatus.approved),
                    child: const Text('Activar'),
                  ),
                ],
            },
          ),
        ),
      ],
    );
  }
}

class _StoreList extends StatelessWidget {
  const _StoreList({super.key, required this.status, required this.empty, required this.actions});

  final StoreStatus status;
  final String empty;
  final List<Widget> Function(Store) actions;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Store>>(
      stream: Repository.instance.watchStoresByStatus(status),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final stores = snap.data!;
        if (stores.isEmpty) return Center(child: Text(empty));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: stores.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _StoreCard(store: stores[i], actions: actions(stores[i])),
            ),
          ),
        );
      },
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store, required this.actions});

  final Store store;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(store.name, style: t.titleMedium)),
                if (store.createdAt != null) Text(_date.format(store.createdAt!), style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            Text([store.address, store.comuna, store.region].where((s) => s.isNotEmpty).join(', '), style: muted),
            Wrap(
              spacing: 16,
              children: [
                // El correo ya no se guarda en el local (que es público): se lee de la cuenta del dueño.
                FutureBuilder<String?>(
                  future: Repository.instance.userEmail(store.ownerUid),
                  builder: (context, snap) {
                    final email = snap.data ?? store.ownerEmail;
                    return email == null ? const SizedBox.shrink() : _Contact(icon: Icons.mail_outline, text: email, style: muted);
                  },
                ),
                if (store.phone != null) _Contact(icon: Icons.phone_outlined, text: store.phone!, style: muted),
              ],
            ),
            if (store.status == StoreStatus.approved || store.status == StoreStatus.suspended)
              StreamBuilder<BankAccount?>(
                stream: Repository.instance.watchBankAccount(store.id),
                builder: (context, snap) => _Contact(
                  icon: Icons.account_balance_outlined,
                  text: snap.data?.summary ?? 'Sin datos bancarios',
                  style: muted,
                ),
              ),
            if (store.statusReason != null) ...[
              const SizedBox(height: 8),
              Text('Motivo: ${store.statusReason}', style: t.bodySmall),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.icon, required this.text, this.style});

  final IconData icon;
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: style?.color),
        const SizedBox(width: 4),
        SelectableText(text, style: style),
      ],
    );
  }
}

/// Cambia el estado, pidiendo motivo cuando corresponde, y confirma con un SnackBar.
Future<void> _changeStatus(BuildContext context, Store store, StoreStatus status, {String? askReason}) async {
  final messenger = ScaffoldMessenger.of(context);
  String? reason;
  if (askReason != null) {
    reason = await showDialog<String>(context: context, builder: (_) => _ReasonDialog(label: askReason));
    if (reason == null) return; // cancelado
  }
  try {
    await Repository.instance.setStoreStatus(store.id, status, reason: reason);
    messenger.showSnackBar(SnackBar(content: Text('${store.name}: ${status.label.toLowerCase()}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.label});

  final String label;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Indica el motivo'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _text,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(labelText: widget.label),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _text.text.trim().isEmpty ? null : () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// Registrar el pago al comercio de sus ventas retiradas que aún no se le pagan.
class _PayoutDialog extends StatefulWidget {
  const _PayoutDialog({required this.store});

  final Store store;

  @override
  State<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends State<_PayoutDialog> {
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final amount = await Repository.instance.createPayout(widget.store.id, _note.text.trim());
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Pago de ${formatClp(amount)} a ${widget.store.name} registrado.')));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'No se pudo registrar.')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchUnpaidOrders(widget.store.id),
      builder: (context, snap) {
        final orders = snap.data ?? const <BagOrder>[];
        final gross = orders.fold<int>(0, (s, o) => s + o.amount);
        final toPay = orders.fold<int>(0, (s, o) => s + o.storeAmount);
        return AlertDialog(
          title: Text('Liquidar a ${widget.store.name}'),
          content: SizedBox(
            width: 420,
            child: !snap.hasData
                ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (orders.isEmpty)
                      const Text('No tiene ventas pendientes de pago.')
                    else ...[
                      Text('${orders.length} ${orders.length == 1 ? 'venta' : 'ventas'} sin liquidar'
                          '${_noShows(orders) > 0 ? ' (${_noShows(orders)} no retiradas por el cliente)' : ''}'),
                      Text('Ventas ${formatClp(gross)} − comisión ${formatClp(gross - toPay)}'),
                      const SizedBox(height: 8),
                      Text('A pagar: ${formatClp(toPay)}', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      const Text('Haz la transferencia al comercio y regístrala aquí:'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _note,
                        decoration: const InputDecoration(labelText: 'Nota (p. ej. n° de transferencia)'),
                      ),
                    ],
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
            if (orders.isNotEmpty)
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Registrando…' : 'Registrar pago')),
          ],
        );
      },
    );
  }
}

int _noShows(List<BagOrder> orders) => orders.where((o) => o.status == OrderStatus.noShow).length;

/// Resumen de lo que hay que pagar a todos los locales, con acceso a "Liquidar todos".
class _PayAllBar extends StatelessWidget {
  const _PayAllBar();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchAllUnpaidOrders(),
      builder: (context, snap) {
        final orders = snap.data ?? const <BagOrder>[];
        final stores = orders.map((o) => o.storeId).toSet().length;
        final amount = orders.fold<int>(0, (s, o) => s + o.storeAmount);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Por pagar a los locales', style: t.bodySmall),
                      Text(formatClp(amount), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        orders.isEmpty
                            ? 'Todo liquidado.'
                            : '${orders.length} ${orders.length == 1 ? 'venta' : 'ventas'} de $stores ${stores == 1 ? 'local' : 'locales'}',
                        style: t.bodySmall,
                      ),
                    ]),
                  ),
                  FilledButton(
                    onPressed: orders.isEmpty
                        ? null
                        : () => showDialog<void>(context: context, builder: (_) => _PayAllDialog(orders: orders)),
                    child: const Text('Liquidar todos'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Liquida a todos los locales de una vez y entrega la planilla para transferir en lote desde el banco.
class _PayAllDialog extends StatefulWidget {
  const _PayAllDialog({required this.orders});

  final List<BagOrder> orders;

  @override
  State<_PayAllDialog> createState() => _PayAllDialogState();
}

class _PayAllDialogState extends State<_PayAllDialog> {
  final _note = TextEditingController();
  bool _saving = false;

  /// Planilla generada después de registrar (null mientras no se registra).
  String? _csv;
  List<Map<String, dynamic>> _done = const [];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payouts = await Repository.instance.createAllPayouts(_note.text.trim());
      String cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
      final rows = ['local,titular,rut,banco,tipo_cuenta,numero_cuenta,correo,monto,ventas,liquidacion'];
      for (final p in payouts) {
        final bank = await Repository.instance.getBankAccount(p['storeId'] as String);
        rows.add([
          p['storeName'], bank?.holder, bank?.rut, bank?.bank, bank?.accountTypeLabel, bank?.accountNumber, bank?.email,
          p['storeAmount'], p['orderCount'], p['payoutId'],
        ].map(cell).join(','));
      }
      if (!mounted) return;
      setState(() {
        _done = payouts;
        _csv = rows.join('\n');
        _saving = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'No se pudo registrar.')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final byStore = <String, List<BagOrder>>{};
    for (final o in widget.orders) {
      byStore.putIfAbsent(o.storeName, () => []).add(o);
    }
    final total = widget.orders.fold<int>(0, (s, o) => s + o.storeAmount);

    if (_csv != null) {
      final paid = _done.fold<int>(0, (s, p) => s + (p['storeAmount'] as num).toInt());
      return AlertDialog(
        title: const Text('Liquidaciones registradas'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_done.length} ${_done.length == 1 ? 'local' : 'locales'} por ${formatClp(paid)}.'),
            const SizedBox(height: 8),
            const Text('Copia la planilla (nombre, RUT, banco, cuenta y monto de cada local) y úsala para las '
                'transferencias desde el banco. Los locales sin datos bancarios salen con esas columnas vacías.'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _csv!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilla copiada (CSV).')));
              }
            },
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Copiar planilla'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Liquidar a todos los locales'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final e in byStore.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Text('${e.key} · ${e.value.length} ${e.value.length == 1 ? 'venta' : 'ventas'}'
                      '${_noShows(e.value) > 0 ? ' (${_noShows(e.value)} no retiradas)' : ''}'),
                ),
                Text(formatClp(e.value.fold<int>(0, (s, o) => s + o.storeAmount))),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(child: Text('Total a transferir', style: t.titleMedium)),
            Text(formatClp(total), style: t.titleLarge),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Nota (p. ej. transferencias semana 40)'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Registrando…' : 'Registrar liquidaciones')),
      ],
    );
  }
}
