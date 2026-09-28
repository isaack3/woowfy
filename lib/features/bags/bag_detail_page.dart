import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class BagDetailPage extends StatelessWidget {
  const BagDetailPage({super.key, required this.bagId});

  final String bagId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
      ),
      body: StreamBuilder<Bag?>(
        stream: Repository.instance.watchBag(bagId),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Esta bolsa ya no está disponible.'));
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final bag = snap.data;
          if (bag == null) return const Center(child: Text('Bolsa no encontrada.'));
          return _Detail(bag: bag);
        },
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.bag});

  final Bag bag;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(bag.storeName, style: t.headlineSmall),
            Text('${bag.address}, ${bag.comuna}', style: t.bodyMedium),
            const SizedBox(height: 16),
            Text(bag.title, style: t.titleLarge),
            const SizedBox(height: 8),
            Text(bag.description.isEmpty
                ? 'Una sorpresa con lo que el local no vendió hoy.'
                : bag.description),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text('Retiro hoy ${formatPickupWindow(bag.pickupStart, bag.pickupEnd)}'),
              subtitle: const Text('Muestra tu código en el local'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(formatClp(bag.price),
                    style: t.headlineMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Text(formatClp(bag.originalPrice),
                    style: t.titleMedium?.copyWith(decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 12),
                Chip(label: Text('-${bag.discountPercent}%')),
              ],
            ),
            const SizedBox(height: 24),
            _ReserveButton(bag: bag),
            const SizedBox(height: 12),
            Text(
              'El contenido varía según lo que quede en el día. Consulta alérgenos directamente en el local.',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReserveButton extends StatefulWidget {
  const _ReserveButton({required this.bag});

  final Bag bag;

  @override
  State<_ReserveButton> createState() => _ReserveButtonState();
}

class _ReserveButtonState extends State<_ReserveButton> {
  bool _busy = false;

  Future<void> _reserve() async {
    if (FirebaseAuth.instance.currentUser == null) {
      context.go('/ingresar?desde=${Uri.encodeComponent('/bolsa/${widget.bag.id}')}');
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await Repository.instance.createOrder(widget.bag.id);
      if (mounted) await openCheckout(context, order.checkoutUrl);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final soldOut = widget.bag.soldOut;
    return FilledButton(
      onPressed: soldOut || _busy ? null : _reserve,
      child: Text(soldOut ? 'Agotada' : (_busy ? 'Reservando…' : 'Reservar y pagar')),
    );
  }
}
