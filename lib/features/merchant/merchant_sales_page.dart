import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/rut.dart';
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
                  const SizedBox(height: 8),
                  _BankCard(storeId: store.id),
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

/// Saldo por cobrar: ventas cerradas (retiradas o no retiradas por el cliente) que Woowfy aún no le paga.
/// Mientras carga o si falla, nunca muestra $0: un monto falso en la pantalla de plata es lo peor que puede pasar.
class _Pending extends StatefulWidget {
  const _Pending({required this.storeId});

  final String storeId;

  @override
  State<_Pending> createState() => _PendingState();
}

class _PendingState extends State<_Pending> {
  late Stream<List<BagOrder>> _orders = Repository.instance.watchUnpaidOrders(widget.storeId);
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cream = t.bodySmall?.copyWith(color: WoowfyColors.cream);
    return StreamBuilder<List<BagOrder>>(
      stream: _orders,
      builder: (context, snap) {
        final orders = snap.data;
        final Widget body;
        if (snap.hasError) {
          body = Row(children: [
            Expanded(child: Text('No pudimos cargar el monto. Revisa tu conexión.', style: cream)),
            TextButton(
              onPressed: () => setState(() => _orders = Repository.instance.watchUnpaidOrders(widget.storeId)),
              style: TextButton.styleFrom(foregroundColor: WoowfyColors.lime),
              child: const Text('Reintentar'),
            ),
          ]);
        } else if (orders == null) {
          body = const _Skeleton(color: Color(0x33FFF7E3));
        } else {
          final amount = orders.fold<int>(0, (s, o) => s + o.storeAmount);
          final sorted = [...orders]..sort((a, b) => b.pickupStart.compareTo(a.pickupStart));
          body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatClp(amount), style: t.headlineLarge?.copyWith(color: WoowfyColors.cream)),
            const SizedBox(height: 4),
            Text(
              orders.isEmpty
                  ? 'No tienes ventas pendientes de pago.'
                  : '${orders.length} ${orders.length == 1 ? 'venta' : 'ventas'} aún sin liquidar (ya descontada la comisión). '
                      'Las bolsas que el cliente no retira también se te pagan.',
              style: cream,
            ),
            if (orders.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(foregroundColor: WoowfyColors.lime, padding: EdgeInsets.zero),
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_open ? 'Ocultar detalle' : 'Ver detalle'),
              ),
              if (_open)
                for (final o in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${formatPickupDay(o.pickupStart)} · ${o.bagTitle}'
                          '${o.status == OrderStatus.noShow ? ' (no retirada)' : ''}',
                          style: cream,
                        ),
                      ),
                      Text(formatClp(o.storeAmount), style: cream?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
            ],
          ]);
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: WoowfyColors.green, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Por recibir', style: t.titleMedium?.copyWith(color: WoowfyColors.lime)),
            const SizedBox(height: 4),
            body,
          ]),
        );
      },
    );
  }
}

/// Barras grises mientras carga un monto (en vez de mostrar $0).
class _Skeleton extends StatelessWidget {
  const _Skeleton({this.color = const Color(0xFFEFE6CF)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        );
    return Semantics(
      label: 'Cargando',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(140, 30), bar(220, 12)]),
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
        if (snap.hasError) {
          return ErrorRetry(
            title: 'No pudimos cargar las ventas',
            error: snap.error,
            onRetry: () => setState(() => _orders = Repository.instance.watchStoreOrdersSince(widget.storeId, _period.since)),
          );
        }
        final orders = snap.data;
        final sold = (orders ?? const <BagOrder>[])
            .where((o) => o.status.isSold)
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
                kpi('Comisión Woowfy ($platformFeePercent)', formatClp(fee)),
                kpi('Para ti ($storeSharePercent)', formatClp(gross - fee), strong: true),
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
    return Reloadable(builder: (context) => StreamBuilder<List<Payout>>(
      stream: Repository.instance.watchPayouts(storeId),
      builder: (context, snap) {
        final payouts = (snap.data ?? const <Payout>[]).where((p) => !p.voided).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pagos recibidos', style: t.titleMedium),
            const SizedBox(height: 8),
            if (snap.hasError)
              ErrorRetry(title: 'No pudimos cargar tus pagos', error: snap.error)
            else if (!snap.hasData)
              const _Skeleton()
            else if (payouts.isEmpty)
              Text('Aún no hay pagos registrados.', style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
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
    ));
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

/// Abre el formulario de la cuenta bancaria (con los datos actuales, si hay).
Future<void> showBankAccountDialog(BuildContext context, String storeId) async {
  final account = await Repository.instance.getBankAccount(storeId).catchError((_) => null);
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => _BankDialog(storeId: storeId, initial: account));
}

/// Cuenta donde el local recibe sus liquidaciones. Es privada: solo la ven el dueño y el admin.
class _BankCard extends StatelessWidget {
  const _BankCard({required this.storeId});

  final String storeId;

  void _edit(BuildContext context, BankAccount? account) => showDialog<void>(
        context: context,
        builder: (_) => _BankDialog(storeId: storeId, initial: account),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<BankAccount?>(
      stream: Repository.instance.watchBankAccount(storeId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final account = snap.data;
        return Card(
          color: account == null ? WoowfyColors.limeSoft : null,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.account_balance_outlined, color: WoowfyColors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      account == null ? 'Recibe tus ventas en tu cuenta' : 'Cuenta para recibir pagos',
                      style: t.titleMedium,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // Dónde está el local en el camino: sin cuenta, en el paso 1; con cuenta, listo para cobrar.
                _PayoutFlow(done: account != null),
                const SizedBox(height: 16),
                if (account == null) ...[
                  Text(
                    'Sin estos datos no podemos transferirte lo que vendes. Toma un minuto.',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _edit(context, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar mi cuenta'),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(color: WoowfyColors.cream, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(account.summary, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                          Text('${account.holder} · ${account.rut}', style: t.bodySmall),
                        ]),
                      ),
                      TextButton(onPressed: () => _edit(context, account), child: const Text('Editar')),
                    ]),
                  ),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.lock_outline, size: 14, color: WoowfyColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Privada: solo la ve el equipo de Woowfy para transferirte.',
                        style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Los 3 pasos de cómo le llega la plata al local, con la línea de avance en verde y lima.
class _PayoutFlow extends StatelessWidget {
  const _PayoutFlow({required this.done});

  /// true cuando el local ya registró su cuenta (el paso 1 queda completo).
  final bool done;

  static const _steps = [
    (Icons.account_balance_outlined, 'Agrega tu cuenta', 'Titular, RUT, banco y número'),
    (Icons.qr_code_scanner, 'Vende y entrega', 'Cada bolsa pagada suma a "Por recibir"'),
    (Icons.payments_outlined, 'Te transferimos', 'Cada semana, ya descontada la comisión'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 460;
      final items = [
        for (var i = 0; i < _steps.length; i++)
          _Step(
            number: i + 1,
            icon: _steps[i].$1,
            title: _steps[i].$2,
            text: _steps[i].$3,
            state: i == 0 ? (done ? _StepState.done : _StepState.current) : (done && i == 1 ? _StepState.current : _StepState.next),
            narrow: narrow,
            t: t,
          ),
      ];
      if (narrow) {
        return Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(width: 2, height: 14, color: WoowfyColors.green.withValues(alpha: 0.25)),
                ),
              ),
          ],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < items.length; i++) ...[
          Expanded(child: items[i]),
          if (i < items.length - 1)
            Padding(
              padding: const EdgeInsets.only(top: 19),
              child: Icon(Icons.arrow_forward, size: 18, color: WoowfyColors.green.withValues(alpha: 0.4)),
            ),
        ],
      ]);
    });
  }
}

enum _StepState { done, current, next }

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
    required this.state,
    required this.narrow,
    required this.t,
  });

  final int number;
  final IconData icon;
  final String title;
  final String text;
  final _StepState state;
  final bool narrow;
  final TextTheme t;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (state) {
      _StepState.done => (WoowfyColors.green, WoowfyColors.lime),
      _StepState.current => (WoowfyColors.lime, WoowfyColors.green),
      _StepState.next => (Colors.white, WoowfyColors.muted),
    };
    final circle = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: state == _StepState.next ? Border.all(color: WoowfyColors.line, width: 1.5) : null,
      ),
      child: Icon(state == _StepState.done ? Icons.check : icon, size: 20, color: fg),
    );
    final label = Column(
      crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text('$number. $title',
            textAlign: narrow ? TextAlign.start : TextAlign.center,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: WoowfyColors.green)),
        Text(text,
            textAlign: narrow ? TextAlign.start : TextAlign.center,
            style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
      ],
    );
    return narrow
        ? Row(children: [circle, const SizedBox(width: 12), Expanded(child: label)])
        : Column(children: [circle, const SizedBox(height: 8), label]);
  }
}

class _BankDialog extends StatefulWidget {
  const _BankDialog({required this.storeId, this.initial});

  final String storeId;
  final BankAccount? initial;

  @override
  State<_BankDialog> createState() => _BankDialogState();
}

class _BankDialogState extends State<_BankDialog> {
  final _form = GlobalKey<FormState>();
  late final _holder = TextEditingController(text: widget.initial?.holder);
  late final _rut = TextEditingController(text: widget.initial?.rut);
  late final _bank = TextEditingController(text: widget.initial?.bank);
  late final _number = TextEditingController(text: widget.initial?.accountNumber);
  late final _email = TextEditingController(text: widget.initial?.email);
  late String _type = widget.initial?.accountType ?? 'vista';
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_holder, _rut, _bank, _number, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v ?? '').trim().isEmpty ? 'Campo obligatorio' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repository.instance.saveBankAccount(
        widget.storeId,
        BankAccount(
          holder: _holder.text.trim(),
          rut: normalizeRut(_rut.text) ?? _rut.text.trim(),
          bank: _bank.text.trim(),
          accountType: _type,
          accountNumber: _number.text.replaceAll(RegExp(r'\s'), ''),
          email: _email.text.trim(),
        ),
      );
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Datos bancarios guardados.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No pudimos guardar. Revisa los datos e intenta de nuevo.')));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cuenta para recibir pagos'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                'Aquí te transferimos lo que vendes cada semana, ya descontada la comisión. '
                'Revisa bien el número: un error puede atrasar tu pago.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _holder,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Titular (persona o empresa)'),
                validator: _required,
              ),
              TextFormField(
                controller: _rut,
                decoration: const InputDecoration(labelText: 'RUT del titular', hintText: '12.345.678-9'),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Campo obligatorio'
                    : normalizeRut(v!) == null
                        ? 'RUT no válido: revisa los números y el dígito verificador.'
                        : null,
              ),
              TextFormField(
                controller: _bank,
                decoration: const InputDecoration(labelText: 'Banco', hintText: 'Banco Estado, Santander…'),
                maxLength: 60,
                validator: _required,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tipo de cuenta'),
                items: [
                  for (final e in BankAccount.accountTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              TextFormField(
                controller: _number,
                maxLength: 30,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Número de cuenta'),
                validator: _required,
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo para el aviso de transferencia (opcional)'),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
      ],
    );
  }
}
