import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis pedidos'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: StreamBuilder<List<BagOrder>>(
        stream: Repository.instance.watchMyOrders(uid),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final orders = snap.data!;
          if (orders.isEmpty) {
            return const Center(child: Text('Aún no tienes pedidos.'));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  return Card(
                    child: ListTile(
                      title: Text('${o.storeName} · ${o.bagTitle}'),
                      subtitle: Text(
                        '${o.pickupStart.day}/${o.pickupStart.month} '
                        '${formatPickupWindow(o.pickupStart, o.pickupEnd)} · ${formatClp(o.amount)}',
                      ),
                      trailing: Chip(label: Text(o.status.label)),
                      onTap: () => context.go('/pedido/${o.id}'),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
