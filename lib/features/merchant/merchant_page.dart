import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../data/chile.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_image.dart';
import 'publish_bag_dialog.dart';
import 'redeem_dialog.dart';
import 'store_profile_dialog.dart';

/// Panel del comercio: solicitar alta, y una vez aprobado, publicar bolsas del día.
class MerchantPage extends StatelessWidget {
  const MerchantPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel del comercio'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: StreamBuilder<Store?>(
        stream: Repository.instance.watchMyStore(uid),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final store = snap.data;
          final Widget child;
          if (store == null) {
            child = _StoreRequestForm(uid: uid);
          } else if (!store.approved) {
            child = _StatusMessage(store: store);
          } else {
            child = _Dashboard(store: store);
          }
          return Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
          );
        },
      ),
    );
  }
}

/// Solicitud pendiente, rechazada o local suspendido.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (store.status) {
      StoreStatus.rejected => (Icons.error_outline, 'Tu solicitud no fue aprobada.'),
      StoreStatus.suspended => (Icons.pause_circle_outline, 'Tu local está suspendido temporalmente.'),
      _ => (
          Icons.hourglass_top,
          'Recibimos tu solicitud. Te contactaremos para validar tu local '
              '(resolución sanitaria y datos de pago) y activarlo.',
        ),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (store.statusReason != null) ...[
            const SizedBox(height: 8),
            Text('Motivo: ${store.statusReason}', textAlign: TextAlign.center),
          ],
          if (store.status == StoreStatus.rejected) ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Repository.instance.resubmitStore(store.id),
              child: const Text('Ya lo corregí, enviar de nuevo'),
            ),
          ],
          if (store.status == StoreStatus.suspended) ...[
            const SizedBox(height: 16),
            const Text('Escríbenos a hola@woowfy.com para más información.'),
          ],
          // Atajo para quien es admin y dueño a la vez: la aprobación se hace en Admin → Solicitudes.
          if (store.status == StoreStatus.pending)
            StreamBuilder<String?>(
              stream: Repository.instance.watchRole(store.ownerUid),
              builder: (context, snap) => snap.data != 'admin'
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: FilledButton.icon(
                        onPressed: () => context.go('/admin'),
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Eres admin: revisar solicitudes'),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _StoreRequestForm extends StatefulWidget {
  const _StoreRequestForm({required this.uid});

  final String uid;

  @override
  State<_StoreRequestForm> createState() => _StoreRequestFormState();
}

class _StoreRequestFormState extends State<_StoreRequestForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _comuna = TextEditingController();
  String? _region;
  String? _category;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _comuna.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await Repository.instance.requestStore(
        uid: widget.uid,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        region: _region!,
        comuna: _comuna.text.trim(),
        address: _address.text.trim(),
        category: _category,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Suma tu local a Woowfy', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Vende lo que no alcanzaste a vender hoy y llega a clientes nuevos.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre del local'),
            validator: required,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: [for (final c in storeCategories) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _category = v),
            validator: (v) => v == null ? 'Elige una categoría' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _region,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Región'),
            items: [for (final r in chileRegions) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => setState(() => _region = v),
            validator: (v) => v == null ? 'Elige una región' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _comuna,
            decoration: const InputDecoration(labelText: 'Comuna'),
            validator: required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Dirección'),
            validator: required,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono de contacto', hintText: '+56 9 1234 5678'),
            validator: required,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Enviando…' : 'Enviar solicitud'),
          ),
          const SizedBox(height: 12),
          const LegalNotice(prefix: 'Al enviar la solicitud aceptas'),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => PublishBagDialog(store: store),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Publicar bolsa'),
      ),
      body: StreamBuilder<List<Bag>>(
        stream: Repository.instance.watchStoreBags(store.id),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final bags = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _ProfileCard(store: store),
              const SizedBox(height: 16),
              _ToPickUp(storeId: store.id),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments_outlined, color: WoowfyColors.green),
                  title: const Text('Ventas y pagos'),
                  subtitle: const Text('Lo vendido, lo que Woowfy te pagó y opiniones'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/merchant/sales'),
                ),
              ),
              const SizedBox(height: 24),
              _Templates(storeId: store.id),
              const SizedBox(height: 24),
              Text('Bolsas publicadas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (bags.isEmpty) const Text('Aún no publicas bolsas. Parte con la de hoy.'),
              for (final bag in bags)
                Card(
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(width: 52, height: 52, child: BagImage(url: bag.imageUrl, iconSize: 20)),
                    ),
                    title: Text('${bag.title} · ${formatClp(bag.price)}${bag.templateId != null ? ' · recurrente' : ''}'),
                    subtitle: Text(
                      '${bag.pickupStart.day}/${bag.pickupStart.month} '
                      '${formatPickupWindow(bag.pickupStart, bag.pickupEnd)} · '
                      'Quedan ${bag.quantityAvailable}',
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: bag.active, onChanged: (v) => Repository.instance.setBagActive(bag.id, v)),
                      if (bag.pickupEnd.isAfter(DateTime.now()))
                        PopupMenuButton<String>(
                          tooltip: 'Más opciones',
                          onSelected: (_) => _cancelBag(context, bag),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'cancel', child: Text('Cancelar la bolsa de hoy')),
                          ],
                        ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Pedidos pagados pendientes de entrega + acceso a validar un código.
class _ToPickUp extends StatelessWidget {
  const _ToPickUp({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<BagOrder>>(
          stream: Repository.instance.watchStoreOrdersToPickUp(storeId),
          builder: (context, snap) {
            final orders = snap.data ?? const <BagOrder>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        snap.hasError
                            ? 'No pudimos cargar los pedidos.'
                            : 'Por retirar: ${orders.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => showDialog<void>(context: context, builder: (_) => const RedeemDialog()),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Validar retiro'),
                    ),
                  ],
                ),
                for (final o in orders)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(o.bagTitle),
                    subtitle: Text('Retiro ${formatPickupWindow(o.pickupStart, o.pickupEnd)}'),
                    trailing: Text(formatClp(o.amount)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Cabecera del panel: logo, nombre, categoría y acceso a editar el perfil.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final incomplete = store.category == null || store.logoUrl == null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              StoreLogo(url: store.logoUrl, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(store.name, style: t.titleLarge),
                  Text(
                    [store.category, store.comuna].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                  ),
                  if (store.hours.isNotEmpty) Text(store.hours, style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                ]),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => StoreProfileDialog(store: store)),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar'),
              ),
            ]),
            if (incomplete) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 18, color: Color(0xFF7A3510)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Completa tu perfil (logo y categoría) para que los clientes te encuentren.')),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bolsas recurrentes del local: se publican solas los días elegidos.
class _Templates extends StatelessWidget {
  const _Templates({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagTemplate>>(
      stream: Repository.instance.watchTemplates(storeId),
      builder: (context, snap) {
        final templates = snap.data ?? const <BagTemplate>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bolsas recurrentes', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              templates.isEmpty
                  ? 'Al publicar, activa "Repetir" y la bolsa se publicará sola los días que elijas.'
                  : 'Se publican solas cada día a las 5:00 (o apenas las creas, si aún es hora).',
              style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
            ),
            const SizedBox(height: 8),
            for (final tpl in templates)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.repeat, color: WoowfyColors.green),
                  title: Text('${tpl.title} · ${formatClp(tpl.price)}'),
                  subtitle: Text('${tpl.daysLabel} · ${tpl.pickupStart} – ${tpl.pickupEnd} · ${tpl.quantity} bolsas'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: tpl.active, onChanged: (v) => Repository.instance.setTemplateActive(tpl.id, v)),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Eliminar bolsa recurrente'),
                            content: const Text('Dejará de publicarse. Las bolsas ya publicadas hoy se mantienen.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                            ],
                          ),
                        );
                        if (ok == true) await Repository.instance.deleteTemplate(tpl.id);
                      },
                    ),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Cancelar la bolsa del día: se despublica, se reembolsa y se avisa a quienes la compraron.
Future<void> _cancelBag(BuildContext context, Bag bag) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cancelar la bolsa de hoy'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se dejará de ofrecer. A quienes ya la pagaron les devolveremos el dinero y les avisaremos.'),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Motivo para los clientes', hintText: 'Cerramos antes por un imprevisto.'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancelar bolsa')),
      ],
    ),
  );
  final text = reason.text.trim();
  reason.dispose();
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final n = await Repository.instance.cancelBag(bag.id, text);
    messenger.showSnackBar(SnackBar(
      content: Text(n == 0 ? 'Bolsa cancelada. Nadie la había comprado.' : 'Bolsa cancelada. Reembolsamos y avisamos a $n ${n == 1 ? 'cliente' : 'clientes'}.'),
    ));
  } on FirebaseFunctionsException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message ?? 'No se pudo cancelar.')));
  }
}
