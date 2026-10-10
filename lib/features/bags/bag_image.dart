import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Foto de la bolsa; si no tiene (o falla la carga), una ilustración de "bolsa sorpresa" (no un ícono de error).
class BagImage extends StatelessWidget {
  const BagImage({super.key, required this.url, this.iconSize = 40});

  final String? url;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: WoowfyColors.limeSoft,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, box) => Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_bag_outlined, size: iconSize, color: WoowfyColors.green),
          // En miniaturas (p. ej. Mis pedidos) solo el ícono.
          if (box.maxWidth > 120) ...[
            const SizedBox(height: 4),
            Text('Bolsa sorpresa',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: WoowfyColors.green, fontWeight: FontWeight.w800)),
          ],
        ]),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null ? child : Container(color: WoowfyColors.limeSoft),
    );
  }
}

/// Logo del local (redondo); si no tiene, un ícono de tienda.
class StoreLogo extends StatelessWidget {
  const StoreLogo({super.key, required this.url, this.size = 48});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.storefront_outlined, size: size * .5, color: WoowfyColors.green);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: WoowfyColors.limeSoft,
        border: Border.all(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null || url!.isEmpty
          ? fallback
          : Image.network(url!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => fallback),
    );
  }
}
