import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Foto de la bolsa; si no tiene (o falla la carga), muestra un ícono de "sin imagen".
class BagImage extends StatelessWidget {
  const BagImage({super.key, required this.url, this.iconSize = 40});

  final String? url;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: WoowfyColors.limeSoft,
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported_outlined, size: iconSize, color: WoowfyColors.green.withValues(alpha: .45)),
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
