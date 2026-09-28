import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
            Text('${store.address}, ${store.comuna}', style: muted),
            Wrap(
              spacing: 16,
              children: [
                if (store.ownerEmail != null) _Contact(icon: Icons.mail_outline, text: store.ownerEmail!, style: muted),
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
