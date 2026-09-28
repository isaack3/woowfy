import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/models.dart';

class BagCard extends StatelessWidget {
  const BagCard({super.key, required this.bag});

  final Bag bag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => context.go('/bolsa/${bag.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 110,
              color: scheme.primaryContainer,
              child: bag.imageUrl != null
                  ? Image.network(bag.imageUrl!, fit: BoxFit.cover)
                  : Icon(Icons.shopping_bag_outlined, size: 48, color: scheme.onPrimaryContainer),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bag.storeName, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${bag.title} · ${bag.comuna}', style: t.bodySmall, maxLines: 1),
                  const SizedBox(height: 6),
                  Text('Retiro hoy ${formatPickupWindow(bag.pickupStart, bag.pickupEnd)}', style: t.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(formatClp(bag.price),
                          style: t.titleLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text(formatClp(bag.originalPrice),
                          style: t.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)),
                      const Spacer(),
                      Text(
                        bag.soldOut ? 'Agotada' : 'Quedan ${bag.quantityAvailable}',
                        style: t.labelMedium?.copyWith(color: bag.soldOut ? scheme.error : null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
