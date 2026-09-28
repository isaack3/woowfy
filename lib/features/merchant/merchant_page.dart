import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'publish_bag_dialog.dart';
import 'redeem_dialog.dart';

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
  String _comuna = pilotComunas.first;
  bool _sending = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await Repository.instance.requestStore(
        uid: widget.uid,
        email: FirebaseAuth.instance.currentUser?.email,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        comuna: _comuna,
        address: _address.text.trim(),
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
            initialValue: _comuna,
            decoration: const InputDecoration(labelText: 'Comuna'),
            items: [for (final c in pilotComunas) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => setState(() => _comuna = v!),
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
              Text(store.name, style: Theme.of(context).textTheme.headlineSmall),
              Text('${store.address}, ${store.comuna}'),
              const SizedBox(height: 16),
              _ToPickUp(storeId: store.id),
              const SizedBox(height: 24),
              Text('Tus bolsas', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (bags.isEmpty) const Text('Aún no publicas bolsas. ¡Parte con la de hoy!'),
              for (final bag in bags)
                Card(
                  child: SwitchListTile(
                    title: Text('${bag.title} · ${formatClp(bag.price)}'),
                    subtitle: Text(
                      '${bag.pickupStart.day}/${bag.pickupStart.month} '
                      '${formatPickupWindow(bag.pickupStart, bag.pickupEnd)} · '
                      'Quedan ${bag.quantityAvailable}',
                    ),
                    value: bag.active,
                    onChanged: (v) => Repository.instance.setBagActive(bag.id, v),
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
