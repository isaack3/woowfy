import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../data/chile.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_image.dart';
import 'merchant_sales_page.dart' show showBankAccountDialog;
import 'publish_bag_dialog.dart';
import 'counter.dart';
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
      body: Reloadable(builder: (context) => StreamBuilder<Store?>(
        stream: Repository.instance.watchMyStore(uid),
        builder: (context, snap) {
          if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar tu local', error: snap.error);
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final store = snap.data;
          final Widget child;
          if (store == null) {
            child = _StoreRequestForm(uid: uid);
          } else if (store.status == StoreStatus.rejected) {
            child = _StoreRequestForm(uid: uid, rejected: store);
          } else if (store.status == StoreStatus.pending) {
            child = _PendingChecklist(store: store);
          } else if (!store.approved) {
            child = _StatusMessage(store: store);
          } else {
            child = _Dashboard(store: store);
          }
          return Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child),
          );
        },
      )),
    );
  }
}

/// Solicitud en revisión: lo que el comercio ya puede ir dejando listo (las reglas lo permiten antes de aprobar).
class _PendingChecklist extends StatelessWidget {
  const _PendingChecklist({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget item({required bool done, required String title, String? subtitle, String? action, VoidCallback? onTap}) => Card(
          child: ListTile(
            leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? WoowfyColors.green : WoowfyColors.muted),
            title: Text(title),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: action == null ? null : TextButton(onPressed: onTap, child: Text(action)),
          ),
        );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.hourglass_top, size: 40, color: WoowfyColors.green),
        const SizedBox(height: 12),
        Text('Tu solicitud está en revisión', style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          'Normalmente la revisamos en 1 día hábil y te contactamos para validar tu local. Mientras, deja todo listo:',
          style: t.bodyMedium?.copyWith(color: WoowfyColors.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        item(done: true, title: 'Solicitud enviada'),
        item(
          done: store.logoUrl != null && store.hours.isNotEmpty,
          title: 'Sube tu logo y horario',
          subtitle: 'Así te verán los clientes',
          action: 'Completar',
          onTap: () => showDialog<void>(context: context, builder: (_) => StoreProfileDialog(store: store)),
        ),
        StreamBuilder<BankAccount?>(
          stream: Repository.instance.watchBankAccount(store.id),
          builder: (context, snap) => item(
            done: snap.data != null,
            title: 'Agrega tu cuenta bancaria',
            subtitle: 'Para transferirte tus ventas',
            action: snap.data == null ? 'Agregar' : 'Editar',
            onTap: () => showBankAccountDialog(context, store.id),
          ),
        ),
        item(
          done: false,
          title: 'Lee la guía para comercios',
          subtitle: 'Precios, entregas y pagos',
          action: 'Abrir',
          onTap: () => launchUrl(Uri.parse('https://woowfy.com/merchants')),
        ),
        // Atajo para quien es admin y dueño a la vez: la aprobación se hace en Admin → Solicitudes.
        StreamBuilder<String?>(
          stream: Repository.instance.watchRole(store.ownerUid),
          builder: (context, snap) => snap.data != 'admin'
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: FilledButton.icon(
                    onPressed: () => context.go('/admin'),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Eres admin: revisar solicitudes'),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Solicitud rechazada o local suspendido.
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
          if (store.status == StoreStatus.suspended) ...[
            const SizedBox(height: 16),
            const Text('Escríbenos a hola@passva.com para más información.'),
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

/// Solicitud de alta. Con [rejected], la misma solicitud con sus datos para corregirla y reenviarla.
class _StoreRequestForm extends StatefulWidget {
  const _StoreRequestForm({required this.uid, this.rejected});

  final String uid;
  final Store? rejected;

  @override
  State<_StoreRequestForm> createState() => _StoreRequestFormState();
}

class _StoreRequestFormState extends State<_StoreRequestForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.rejected?.name);
  late final _address = TextEditingController(text: widget.rejected?.address);
  late final _phone = TextEditingController(text: widget.rejected?.phone);
  late final _comuna = TextEditingController(text: widget.rejected?.comuna);
  late String? _region = chileRegions.contains(widget.rejected?.region) ? widget.rejected!.region : null;
  late String? _category =
      storeCategories.contains(widget.rejected?.category) ? widget.rejected!.category : null;
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
      final rejected = widget.rejected;
      if (rejected != null) {
        await Repository.instance.resubmitStore(rejected.id, {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'region': _region!,
          'comuna': _comuna.text.trim(),
          'address': _address.text.trim(),
          'category': _category,
        });
        return;
      }
      await Repository.instance.requestStore(
        uid: widget.uid,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        region: _region!,
        comuna: _comuna.text.trim(),
        address: _address.text.trim(),
        category: _category,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, fallback: 'No pudimos enviar la solicitud. Intenta de nuevo.'))),
        );
      }
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
          if (widget.rejected != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tu solicitud no fue aprobada', style: Theme.of(context).textTheme.titleMedium),
                if (widget.rejected!.statusReason != null) ...[
                  const SizedBox(height: 4),
                  Text('Motivo: ${widget.rejected!.statusReason}'),
                ],
                const SizedBox(height: 4),
                const Text('Corrige tus datos y envíala de nuevo. Si tienes dudas, escríbenos a hola@passva.com.'),
              ]),
            )
          else ...[
            Text('Suma tu local a Woowfy', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Vende lo que no alcanzaste a vender hoy y llega a clientes nuevos.'),
          ],
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
            child: Text(_sending
                ? 'Enviando…'
                : widget.rejected != null
                    ? 'Guardar y enviar de nuevo'
                    : 'Enviar solicitud'),
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
    return Reloadable(builder: (context) => StreamBuilder<List<Bag>>(
      stream: Repository.instance.watchStoreBags(store.id),
      builder: (context, snap) {
        final bags = snap.data ?? const <Bag>[];
        final now = DateTime.now();
        final current = bags.where((b) => b.pickupEnd.isAfter(now)).toList().reversed.toList();
        final past = bags.where((b) => !b.pickupEnd.isAfter(now)).toList();
        // "Igual que ayer": la bolsa publicada más reciente.
        final latest = bags.isEmpty ? null : bags.first;
        return Scaffold(
          floatingActionButton: _MainAction(store: store, current: current, latest: latest),
          body: snap.hasError
              ? ErrorRetry(title: 'No pudimos cargar tus bolsas', error: snap.error)
              : !snap.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        _ProfileCard(store: store),
                        const SizedBox(height: 12),
                        _ToPickUp(storeId: store.id),
                        const SizedBox(height: 24),
                        Text('Hoy y próximas', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if (current.isEmpty)
                          Text(
                            latest == null
                                ? 'Aún no publicas bolsas. Parte con la de hoy.'
                                : 'No tienes bolsas publicadas para hoy. "Publicar bolsa" parte con los datos de la última.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: WoowfyColors.muted),
                          ),
                        for (final bag in current) _BagTile(store: store, bag: bag),
                        const SizedBox(height: 24),
                        _Templates(store: store),
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.payments_outlined, color: WoowfyColors.green),
                            title: const Text('Ventas y pagos'),
                            subtitle: const Text('Lo vendido, lo que Woowfy te pagó y opiniones'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.go('/merchant/sales'),
                          ),
                        ),
                        if (past.isNotEmpty)
                          Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text('Anteriores (${past.length})', style: Theme.of(context).textTheme.titleMedium),
                              children: [for (final bag in past) _BagTile(store: store, bag: bag)],
                            ),
                          ),
                        const SizedBox(height: 8),
                        const _GuideCard(),
                      ],
                    ),
        );
      },
    ));
  }
}

/// Botón flotante: "Publicar bolsa", salvo en hora de retiro (desde 30 min antes hasta que termina), cuando el
/// pulgar necesita "Validar retiro" y publicar pasa a un botón chico al lado.
class _MainAction extends StatefulWidget {
  const _MainAction({required this.store, required this.current, required this.latest});

  final Store store;
  final List<Bag> current;
  final Bag? latest;

  @override
  State<_MainAction> createState() => _MainActionState();
}

class _MainActionState extends State<_MainAction> {
  // Cambia solo con la hora, sin que nadie toque nada.
  late final Timer _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rush = widget.current.any(
        (b) => now.isAfter(b.pickupStart.subtract(const Duration(minutes: 30))) && now.isBefore(b.pickupEnd));
    void publish() => publishBag(context, widget.store, from: widget.latest);
    if (!rush) {
      return FloatingActionButton.extended(
        heroTag: 'publish',
        onPressed: publish,
        icon: const Icon(Icons.add),
        label: const Text('Publicar bolsa'),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FloatingActionButton.small(
        heroTag: 'publish',
        tooltip: 'Publicar bolsa',
        backgroundColor: WoowfyColors.cream,
        foregroundColor: WoowfyColors.green,
        onPressed: publish,
        child: const Icon(Icons.add),
      ),
      const SizedBox(width: 12),
      FloatingActionButton.extended(
        heroTag: 'redeem',
        backgroundColor: WoowfyColors.green,
        foregroundColor: WoowfyColors.cream,
        onPressed: () => openCounter(context),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Validar retiro'),
      ),
    ]);
  }
}

/// Pedidos pagados pendientes de entrega + acceso a validar un código.
class _ToPickUp extends StatelessWidget {
  const _ToPickUp({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cream = t.bodyMedium?.copyWith(color: WoowfyColors.cream);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: WoowfyColors.green, borderRadius: BorderRadius.circular(20)),
      child: StreamBuilder<List<BagOrder>>(
        stream: Repository.instance.watchStoreOrdersToPickUp(storeId),
        builder: (context, snap) {
          final orders = snap.data ?? const <BagOrder>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ahora', style: t.titleMedium?.copyWith(color: WoowfyColors.lime)),
              Text(
                snap.hasError
                    ? 'No pudimos cargar los pedidos.'
                    : !snap.hasData
                        ? 'Cargando pedidos…'
                        : orders.isEmpty
                            ? 'Nadie por retirar en este momento'
                            : '${orders.length} por retirar',
                style: t.titleLarge?.copyWith(color: WoowfyColors.cream),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => openCounter(context, pending: snap.hasData ? orders.length : null),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Validar retiro'),
              ),
              for (final o in orders.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: Text('${o.bagTitle} · ${formatPickup(o.pickupStart, o.pickupEnd)}', style: cream)),
                    Text(formatClp(o.amount), style: cream),
                  ]),
                ),
              if (orders.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('y ${orders.length - 5} más', style: t.bodySmall?.copyWith(color: WoowfyColors.cream)),
                ),
            ],
          );
        },
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
              IconButton(
                tooltip: 'Editar perfil del local',
                onPressed: () => showDialog<void>(context: context, builder: (_) => StoreProfileDialog(store: store)),
                icon: const Icon(Icons.edit_outlined),
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
  const _Templates({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagTemplate>>(
      stream: Repository.instance.watchTemplates(store.id),
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
                    Semantics(
                      label: 'Se publica sola: ${tpl.title}',
                      child: Switch(value: tpl.active, onChanged: (v) => Repository.instance.setTemplateActive(tpl.id, v)),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => PublishBagDialog(store: store, editTemplate: tpl),
                      ),
                    ),
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

/// Publica (vacía o "igual que" [from]) y, al terminar, ofrece verla como cliente. Tocar fuera no la cierra.
Future<void> publishBag(BuildContext context, Store store, {Bag? from}) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final id = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PublishBagDialog(store: store, from: from),
  );
  if (id == null) return;
  messenger.showSnackBar(SnackBar(
    content: const Text('Bolsa publicada: ya la ven los clientes.'),
    action: SnackBarAction(label: 'Ver como cliente', onPressed: () => router.go('/bag/$id')),
  ));
}

/// Una bolsa en el panel: visible o no, y menú con editar, publicar de nuevo y cancelar.
class _BagTile extends StatelessWidget {
  const _BagTile({required this.store, required this.bag});

  final Store store;
  final Bag bag;

  @override
  Widget build(BuildContext context) {
    final upcoming = bag.pickupEnd.isAfter(DateTime.now());
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 52, height: 52, child: BagImage(url: bag.imageUrl, iconSize: 20)),
        ),
        title: Text('${bag.title} · ${formatClp(bag.price)}'),
        subtitle: Text([
          formatPickup(bag.pickupStart, bag.pickupEnd),
          if (upcoming) 'Quedan ${bag.quantityAvailable}',
          if (bag.templateId != null) 'recurrente',
        ].join(' · ')),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (upcoming)
            Semantics(
              label: 'Visible para clientes: ${bag.title}',
              child: Switch(value: bag.active, onChanged: (v) => Repository.instance.setBagActive(bag.id, v)),
            ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) => switch (v) {
              'edit' => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => PublishBagDialog(store: store, editBag: bag),
                ),
              'again' => publishBag(context, store, from: bag),
              _ => _cancelBag(context, bag),
            },
            itemBuilder: (_) => [
              if (upcoming)
                const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
              const PopupMenuItem(value: 'again', child: ListTile(leading: Icon(Icons.copy_outlined), title: Text('Publicar de nuevo'))),
              if (upcoming)
                const PopupMenuItem(
                  value: 'cancel',
                  child: ListTile(leading: Icon(Icons.cancel_outlined), title: Text('Cancelar la bolsa de hoy')),
                ),
            ],
          ),
        ]),
      ),
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
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo cancelar. Intenta de nuevo.'))));
  }
}

/// Enlace a la guía para comercios (woowfy.com/merchants): cómo publicar, entregar, cancelar y cobrar.
class _GuideCard extends StatelessWidget {
  const _GuideCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined, color: WoowfyColors.green),
        title: const Text('Guía para comercios'),
        subtitle: const Text('Consejos para publicar, entregar y cobrar'),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => launchUrl(Uri.parse('https://woowfy.com/merchants')),
      ),
    );
  }
}
