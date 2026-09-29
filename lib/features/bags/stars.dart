import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Estrellas de 0 a 5 (admite medias estrellas).
class Stars extends StatelessWidget {
  const Stars({super.key, required this.value, this.size = 16});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star_rounded
                : value >= i - .5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: WoowfyColors.orange,
          ),
      ],
    );
  }
}

/// "★ 4,6 (23)" compacto para tarjetas; nada si el local aún no tiene calificaciones.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.avg, required this.count, this.size = 14});

  final double? avg;
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (avg == null || count == 0) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: size + 2, color: WoowfyColors.orange),
      const SizedBox(width: 2),
      Text('${formatRating(avg!)} ($count)',
          style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w700, color: WoowfyColors.green)),
    ]);
  }
}
