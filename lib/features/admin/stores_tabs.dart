import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
      stream: Repository.instance.watchUnpaidPickedUp(widget.store.id),
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
                      const Text('No tiene ventas retiradas pendientes de pago.')
                    else ...[
                      Text('${orders.length} ${orders.length == 1 ? 'bolsa retirada' : 'bolsas retiradas'} sin liquidar'),
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
