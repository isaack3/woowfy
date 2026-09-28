import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'bag_image.dart';

class BagCard extends StatelessWidget {
  const BagCard({super.key, required this.bag, this.distance});

  final Bag bag;

  /// Distancia al usuario ya formateada ("1,2 km"), si se conoce.
  final String? distance;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => context.go('/bag/${bag.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 130,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BagImage(url: bag.imageUrl),
                  Positioned(top: 10, left: 10, child: DiscountPill(bag.discountPercent)),
                  if (bag.soldOut)
                    Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: const Text('Agotada', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    StoreLogo(url: bag.storeLogoUrl, size: 26),
                    const SizedBox(width: 8),
                    Expanded(child: Text(bag.storeName, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 4),
                  Text([bag.title, bag.category, bag.comuna].whereType<String>().where((s) => s.isNotEmpty).join(' · '), style: t.bodySmall?.copyWith(color: WoowfyColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.schedule, size: 14, color: WoowfyColors.muted),
                    const SizedBox(width: 4),
                    Text('Retiro hoy ${formatPickupWindow(bag.pickupStart, bag.pickupEnd)}',
                        style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                    if (distance != null) ...[
                      const Spacer(),
                      const Icon(Icons.near_me_outlined, size: 14, color: WoowfyColors.green),
                      const SizedBox(width: 2),
                      Text(distance!, style: t.bodySmall?.copyWith(color: WoowfyColors.green, fontWeight: FontWeight.w700)),
                    ],
                  ]),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(formatClp(bag.price),
                          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: WoowfyColors.green)),
                      const SizedBox(width: 8),
                      Text(formatClp(bag.originalPrice),
                          style: t.bodySmall?.copyWith(decoration: TextDecoration.lineThrough, color: WoowfyColors.muted)),
                      const Spacer(),
                      if (!bag.soldOut)
                        Text('Quedan ${bag.quantityAvailable}', style: t.labelMedium?.copyWith(color: WoowfyColors.muted)),
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
