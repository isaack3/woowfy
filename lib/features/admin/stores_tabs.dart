import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
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
        // Sin resolución sanitaria no se aprueba (también lo exigen las reglas de Firestore).
        FilledButton(
          onPressed: store.hasSanitaryPermit ? () => _changeStatus(context, store, StoreStatus.approved) : null,
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
                  OutlinedButton(
                    onPressed: () => _changeStatus(context, store, StoreStatus.suspended,
                        askReason: 'Motivo de la suspensión (lo verá el comercio)'),
                    child: const Text('Suspender'),
                  ),
                ],
              StoreStatus.suspended => [
                  FilledButton.tonal(
                    onPressed: store.hasSanitaryPermit ? () => _changeStatus(context, store, StoreStatus.approved) : null,
                    child: const Text('Activar'),
                  ),
                ],
              _ => [
                  FilledButton.tonal(
                    onPressed: store.hasSanitaryPermit ? () => _changeStatus(context, store, StoreStatus.approved) : null,
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
    return Reloadable(builder: (context) => StreamBuilder<List<Store>>(
      stream: Repository.instance.watchStoresByStatus(status),
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar los comercios', error: snap.error);
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
    ));
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
            store.hasSanitaryPermit
                ? _Contact(icon: Icons.verified_outlined, text: 'Resolución sanitaria N° ${store.sanitaryPermit}', style: muted)
                : _Contact(
                    icon: Icons.warning_amber_outlined,
                    text: 'Sin resolución sanitaria: pídela al local antes de aprobarlo',
                    style: muted?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
            if (store.status == StoreStatus.approved || store.status == StoreStatus.suspended)
              StreamBuilder<BankAccount?>(
                stream: Repository.instance.watchBankAccount(store.id),
                builder: (context, snap) => _Contact(
                  icon: Icons.account_balance_outlined,
                  text: snap.hasError
                      ? 'No pudimos leer la cuenta bancaria'
                      : !snap.hasData && snap.connectionState == ConnectionState.waiting
                          ? 'Cargando cuenta bancaria…'
                          : snap.data?.summary ?? 'Sin datos bancarios',
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
        Flexible(child: SelectableText(text, style: style)),
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
  final previous = store.status;
  try {
    await Repository.instance.setStoreStatus(store.id, status, reason: reason);
    final text = switch (status) {
      StoreStatus.approved => '${store.name} ya puede publicar bolsas.',
      StoreStatus.suspended => '${store.name} quedó suspendido: sus bolsas se pausaron.',
      StoreStatus.rejected => 'Solicitud de ${store.name} rechazada.',
      StoreStatus.pending => '${store.name} volvió a revisión.',
    };
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Deshacer',
        onPressed: () => Repository.instance
            .setStoreStatus(store.id, previous, reason: store.statusReason)
            .catchError((Object e) => messenger.showSnackBar(
                SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo deshacer.'))))),
      ),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo actualizar. Intenta de nuevo.'))));
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
class PayoutDialog extends StatefulWidget {
  const PayoutDialog({super.key, required this.storeId, required this.storeName});

  final String storeId;
  final String storeName;

  @override
  State<PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends State<PayoutDialog> {
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
      final amount = await Repository.instance.createPayout(widget.storeId, _note.text.trim());
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Pago de ${formatClp(amount)} a ${widget.storeName} registrado.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo registrar el pago.'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BankAccount?>(
      stream: Repository.instance.watchBankAccount(widget.storeId),
      builder: (context, bankSnap) => StreamBuilder<List<BagOrder>>(
        stream: Repository.instance.watchUnpaidOrders(widget.storeId),
        builder: (context, snap) {
          final orders = snap.data ?? const <BagOrder>[];
          final gross = orders.fold<int>(0, (s, o) => s + o.amount);
          final toPay = orders.fold<int>(0, (s, o) => s + o.storeAmount);
          final loading = !snap.hasData || bankSnap.connectionState == ConnectionState.waiting;
          final bank = bankSnap.data;
          return AlertDialog(
            title: Text('Liquidar a ${widget.storeName}'),
            content: SizedBox(
              width: 440,
              child: loading
                  ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
                  : SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (orders.isEmpty)
                          const Text('No tiene ventas pendientes de pago.')
                        else ...[
                          Text('${orders.length} ${orders.length == 1 ? 'venta' : 'ventas'} sin liquidar'
                              '${_noShows(orders) > 0 ? ' (${_noShows(orders)} no retiradas por el cliente)' : ''}'),
                          Text('Ventas ${formatClp(gross)} − comisión ${formatClp(gross - toPay)}'),
                          const SizedBox(height: 8),
                          Text('A pagar: ${formatClp(toPay)}', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          if (bank == null)
                            const _Notice(
                              text: 'Este local aún no registra su cuenta bancaria. Sus ventas quedan pendientes '
                                  'hasta que la agregue en "Ventas y pagos".',
                            )
                          else ...[
                            const Text('Primero transfiere a esta cuenta; después registra el pago aquí:'),
                            const SizedBox(height: 8),
                            _BankDetails(bank: bank, amount: toPay),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _note,
                              decoration: const InputDecoration(labelText: 'Nota (p. ej. n° de transferencia)'),
                            ),
                          ],
                        ],
                      ]),
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
              if (orders.isNotEmpty && bank != null)
                FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Registrando…' : 'Registrar pago')),
            ],
          );
        },
      ),
    );
  }
}

/// Datos de la cuenta de destino, cada uno con su botón de copiar (para pegar en el banco).
class _BankDetails extends StatelessWidget {
  const _BankDetails({required this.bank, required this.amount});

  final BankAccount bank;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Titular', bank.holder),
      ('RUT', bank.rut),
      ('Banco', bank.bank),
      ('Tipo', bank.accountTypeLabel),
      ('Número', bank.accountNumber),
      if (bank.email.isNotEmpty) ('Correo', bank.email),
      ('Monto', '$amount'),
    ];
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(children: [
          for (final (label, value) in rows)
            Row(children: [
              SizedBox(width: 64, child: Text(label, style: muted)),
              Expanded(child: SelectableText(label == 'Monto' ? formatClp(amount) : value)),
              IconButton(
                tooltip: 'Copiar $label',
                icon: const Icon(Icons.copy, size: 16),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copiado.')));
                  }
                },
              ),
            ]),
        ]),
      ),
    );
  }
}

/// Aviso destacado dentro de un diálogo (p. ej. locales sin cuenta bancaria).
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18, color: WoowfyColors.green),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

int _noShows(List<BagOrder> orders) => orders.where((o) => o.status == OrderStatus.noShow).length;

/// Resumen de lo que hay que pagar a todos los locales, con acceso a "Liquidar todos".
class PayAllBar extends StatelessWidget {
  const PayAllBar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchAllUnpaidOrders(),
      builder: (context, snap) {
        final loaded = snap.hasData && !snap.hasError;
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
                      Text(loaded ? formatClp(amount) : '…', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      Text(
                        snap.hasError
                            ? 'No pudimos calcular el monto. Recarga la página.'
                            : !loaded
                                ? 'Calculando…'
                                : orders.isEmpty
                                    ? 'Todo liquidado.'
                                    : '${orders.length} ${orders.length == 1 ? 'venta' : 'ventas'} de $stores ${stores == 1 ? 'local' : 'locales'}',
                        style: t.bodySmall,
                      ),
                    ]),
                  ),
                  FilledButton(
                    onPressed: !loaded || orders.isEmpty
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => _PayAllDialog(orders: orders),
                          ),
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
/// Primero muestra la vista previa (con la planilla ya copiable); los locales sin cuenta bancaria quedan fuera.
class _PayAllDialog extends StatefulWidget {
  const _PayAllDialog({required this.orders});

  final List<BagOrder> orders;

  @override
  State<_PayAllDialog> createState() => _PayAllDialogState();
}

class _PayAllDialogState extends State<_PayAllDialog> {
  final _note = TextEditingController();
  late final Future<Map<String, BankAccount?>> _banks = _loadBanks();
  bool _saving = false;
  bool _copied = false;

  /// Liquidaciones ya registradas (null mientras no se registra).
  List<Map<String, dynamic>>? _done;

  Future<Map<String, BankAccount?>> _loadBanks() async {
    final ids = widget.orders.map((o) => o.storeId).toSet().toList();
    final accounts = await Future.wait(ids.map(Repository.instance.getBankAccount));
    return {for (var i = 0; i < ids.length; i++) ids[i]: accounts[i]};
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  static String _cell(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';

  /// Planilla para la transferencia en lote: una fila por local.
  static String _csv(List<({String name, BankAccount bank, int amount, int count, String? payoutId})> rows) => [
        'local,titular,rut,banco,tipo_cuenta,numero_cuenta,correo,monto,ventas,liquidacion',
        for (final r in rows)
          [r.name, r.bank.holder, r.bank.rut, r.bank.bank, r.bank.accountTypeLabel, r.bank.accountNumber, r.bank.email,
                  r.amount, r.count, r.payoutId]
              .map(_cell)
              .join(','),
      ].join('\n');

  Future<void> _copy(String csv) async {
    await Clipboard.setData(ClipboardData(text: csv));
    setState(() => _copied = true);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Planilla copiada (CSV).')));
  }

  Future<void> _save(List<String> storeIds) async {
    setState(() => _saving = true);
    try {
      final payouts = await Repository.instance.createAllPayouts(_note.text.trim(), storeIds);
      if (!mounted) return;
      setState(() {
        _done = payouts;
        _copied = false; // la planilla final (con los montos registrados) aún no se copia
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudieron registrar las liquidaciones.'))));
      setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    if (_done != null && _done!.isNotEmpty && !_copied) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Cerrar sin copiar la planilla?'),
          content: const Text('Los pagos ya quedaron registrados. Sin la planilla tendrás que armar las transferencias '
              'a mano con los datos de cada local.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar igual')),
            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, BankAccount?>>(
      future: _banks,
      builder: (context, snap) {
        if (snap.hasError) {
          return AlertDialog(
            title: const Text('Liquidar a todos los locales'),
            content: Text(friendlyError(snap.error!, fallback: 'No pudimos leer las cuentas bancarias de los locales.')),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
          );
        }
        if (!snap.hasData) {
          return const AlertDialog(
            title: Text('Liquidar a todos los locales'),
            content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
          );
        }
        return _done == null ? _preview(context, snap.data!) : _result(context, snap.data!);
      },
    );
  }

  Widget _preview(BuildContext context, Map<String, BankAccount?> banks) {
    final t = Theme.of(context).textTheme;
    final byStore = <String, List<BagOrder>>{};
    for (final o in widget.orders) {
      byStore.putIfAbsent(o.storeId, () => []).add(o);
    }
    int sum(List<BagOrder> l) => l.fold<int>(0, (s, o) => s + o.storeAmount);
    final ready = byStore.entries.where((e) => banks[e.key] != null).toList();
    final missing = byStore.entries.where((e) => banks[e.key] == null).toList();
    final total = ready.fold<int>(0, (s, e) => s + sum(e.value));
    final csv = _csv([
      for (final e in ready)
        (name: e.value.first.storeName, bank: banks[e.key]!, amount: sum(e.value), count: e.value.length, payoutId: null),
    ]);

    return AlertDialog(
      title: const Text('Liquidar a todos los locales'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final e in ready)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('${e.value.first.storeName} · ${e.value.length} ${e.value.length == 1 ? 'venta' : 'ventas'}'
                        '${_noShows(e.value) > 0 ? ' (${_noShows(e.value)} no retiradas)' : ''}'),
                  ),
                  Text(formatClp(sum(e.value))),
                ]),
              ),
            if (missing.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Notice(
                text: '${missing.length == 1 ? '1 local no tiene' : '${missing.length} locales no tienen'} cuenta bancaria '
                    'y ${missing.length == 1 ? 'queda' : 'quedan'} fuera: '
                    '${missing.map((e) => '${e.value.first.storeName} (${formatClp(sum(e.value))})').join(', ')}. '
                    'Sus ventas siguen pendientes hasta que la registren.',
              ),
            ],
            const Divider(height: 24),
            Row(children: [
              Expanded(child: Text('Total a transferir', style: t.titleMedium)),
              Text(formatClp(total), style: t.titleLarge),
            ]),
            if (ready.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Nota (p. ej. transferencias semana 40)'),
              ),
              const SizedBox(height: 8),
              Text('Copia la planilla, haz las transferencias en el banco y después registra: estas ventas quedan como pagadas. '
                  'Si algo falla, puedes anular una liquidación desde el historial.',
                  style: t.bodySmall),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        if (ready.isNotEmpty) ...[
          OutlinedButton.icon(
            onPressed: () => _copy(csv),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Copiar planilla'),
          ),
          FilledButton(
            onPressed: _saving ? null : () => _save([for (final e in ready) e.key]),
            child: Text(_saving
                ? 'Registrando…'
                : 'Registrar ${ready.length} ${ready.length == 1 ? 'pago' : 'pagos'}'),
          ),
        ],
      ],
    );
  }

  Widget _result(BuildContext context, Map<String, BankAccount?> banks) {
    final done = _done!;
    final paid = done.fold<int>(0, (s, p) => s + (p['storeAmount'] as num).toInt());
    final rows = [
      for (final p in done)
        if (banks[p['storeId']] != null)
          (
            name: p['storeName'] as String,
            bank: banks[p['storeId']]!,
            amount: (p['storeAmount'] as num).toInt(),
            count: (p['orderCount'] as num).toInt(),
            payoutId: p['payoutId'] as String?,
          ),
    ];
    final csv = _csv(rows);
    return AlertDialog(
      title: const Text('Liquidaciones registradas'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(done.isEmpty
              ? 'No había ventas por liquidar en esos locales.'
              : '${done.length} ${done.length == 1 ? 'local' : 'locales'} por ${formatClp(paid)}.'),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Copia la planilla final (con los montos registrados) y úsala para las transferencias desde el banco.'),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _close, child: const Text('Cerrar')),
        if (done.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _copy(csv),
            icon: Icon(_copied ? Icons.check : Icons.table_view_outlined, size: 18),
            label: Text(_copied ? 'Planilla copiada' : 'Copiar planilla'),
          ),
      ],
    );
  }
}
