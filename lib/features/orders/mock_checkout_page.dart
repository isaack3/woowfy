import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Reemplaza al checkout de Mercado Pago mientras no haya credenciales.
/// Ningún dinero real se mueve: solo cambia el estado de la orden.
class MockCheckoutPage extends StatefulWidget {
  const MockCheckoutPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<MockCheckoutPage> createState() => _MockCheckoutPageState();
}

class _MockCheckoutPageState extends State<MockCheckoutPage> {
  bool _busy = false;

  Future<void> _resolve(bool approved) async {
    setState(() => _busy = true);
    try {
      await Repository.instance.confirmMockPayment(widget.orderId, approved: approved);
      if (mounted) context.go('/order/${widget.orderId}');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pago simulado')),
      body: StreamBuilder<BagOrder?>(
        stream: Repository.instance.watchOrder(widget.orderId),
        builder: (context, snap) {
          final order = snap.data;
          if (order == null) return const Center(child: CircularProgressIndicator());
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.science_outlined),
                      title: Text('Modo de prueba'),
                      subtitle: Text('Aquí aparecerá el checkout de Mercado Pago. No se cobra nada.'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(order.storeName, style: t.titleMedium),
                  Text(order.bagTitle),
                  const SizedBox(height: 8),
                  Text(formatClp(order.amount), style: t.headlineMedium),
                  const SizedBox(height: 24),
                  if (order.status != OrderStatus.pendingPayment)
                    FilledButton(
                      onPressed: () => context.go('/order/${order.id}'),
                      child: Text('Ver pedido (${order.status.label.toLowerCase()})'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _resolve(true),
                      icon: const Icon(Icons.check),
                      label: const Text('Simular pago aprobado'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _resolve(false),
                      child: const Text('Simular pago rechazado'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
