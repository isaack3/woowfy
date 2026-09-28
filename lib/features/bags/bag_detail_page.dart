import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'bag_image.dart';

class BagDetailPage extends StatelessWidget {
  const BagDetailPage({super.key, required this.bagId});

  final String bagId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Bag?>(
      stream: Repository.instance.watchBag(bagId),
      builder: (context, snap) {
        final bag = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const WoowfyLogo(onDark: true),
            leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/')),
            actions: [
              if (bag != null) ...[
                _FavoriteButton(bag: bag),
                IconButton(tooltip: 'Compartir', icon: const Icon(Icons.share_outlined), onPressed: () => _share(context, bag)),
              ],
              const SizedBox(width: 4),
            ],
          ),
          body: snap.hasError
              ? const Center(child: Text('Esta bolsa ya no está disponible.'))
              : snap.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : bag == null
                      ? const Center(child: Text('Bolsa no encontrada.'))
                      : _Detail(bag: bag),
        );
      },
    );
  }

  /// Comparte el enlace de la bolsa (WhatsApp, etc. con el menú nativo; si no existe, copia el enlace).
  Future<void> _share(BuildContext context, Bag bag) async {
    final url = 'https://app.woowfy.com/bag/${bag.id}';
    final text = '${bag.storeName} tiene una bolsa sorpresa a ${formatClp(bag.price)} '
        '(normalmente ${formatClp(bag.originalPrice)}). Rescátala en Woowfy: $url';
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await SharePlus.instance.share(ShareParams(text: text, subject: 'Bolsa sorpresa en Woowfy'));
      if (result.status == ShareResultStatus.unavailable) throw Exception('sin menú de compartir');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(const SnackBar(content: Text('Enlace copiado. Pégalo en WhatsApp o donde quieras.')));
    }
  }
}

/// Corazón para seguir al local: te avisamos cuando publique bolsas.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.bag});

  final Bag bag;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return IconButton(
        tooltip: 'Seguir a este local',
        icon: const Icon(Icons.favorite_border),
        onPressed: () => context.go('/login?from=${Uri.encodeComponent('/bag/${bag.id}')}'),
      );
    }
    return StreamBuilder<Set<String>>(
      stream: Repository.instance.watchFavoriteStoreIds(uid),
      builder: (context, snap) {
        final fav = snap.data?.contains(bag.storeId) ?? false;
        return IconButton(
          tooltip: fav ? 'Dejar de seguir' : 'Seguir a este local',
          icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? WoowfyColors.coral : null),
          onPressed: () async {
            await Repository.instance.setFavorite(uid, storeId: bag.storeId, storeName: bag.storeName, favorite: !fav);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(fav
                  ? 'Dejaste de seguir a ${bag.storeName}'
                  : 'Sigues a ${bag.storeName}. Activa las notificaciones en Cuenta para saber cuando publique.'),
            ));
          },
        );
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.bag});

  final Bag bag;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(fit: StackFit.expand, children: [
                  BagImage(url: bag.imageUrl, iconSize: 56),
                  Positioned(top: 12, left: 12, child: DiscountPill(bag.discountPercent)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              StoreLogo(url: bag.storeLogoUrl, size: 44),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(bag.storeName, style: t.headlineSmall),
                  if (bag.category != null) Text(bag.category!, style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.place_outlined, size: 16, color: WoowfyColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text([bag.address, bag.comuna, bag.region].where((s) => s.isNotEmpty).join(', '),
                    style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
              ),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bag.title, style: t.titleLarge),
                    const SizedBox(height: 6),
                    Text(bag.description.isEmpty ? 'Una sorpresa con lo que el local no vendió hoy.' : bag.description),
                    const Divider(height: 28),
                    Row(children: [
                      const Icon(Icons.schedule, color: WoowfyColors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Retiro hoy ${formatPickupWindow(bag.pickupStart, bag.pickupEnd)}', style: t.titleMedium),
                          Text('Muestra tu código QR en el local', style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(formatClp(bag.price), style: t.headlineMedium?.copyWith(color: WoowfyColors.green)),
                        const SizedBox(width: 10),
                        Text(formatClp(bag.originalPrice),
                            style: t.titleMedium?.copyWith(decoration: TextDecoration.lineThrough, color: WoowfyColors.muted)),
                        const Spacer(),
                        if (!bag.soldOut) Text('Quedan ${bag.quantityAvailable}', style: t.labelLarge),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ReserveButton(bag: bag),
            const SizedBox(height: 12),
            Text(
              'El contenido varía según lo que quede en el día. Consulta alérgenos directamente en el local.',
              style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
              textAlign: TextAlign.center,
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
      context.go('/login?from=${Uri.encodeComponent('/bag/${widget.bag.id}')}');
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
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: soldOut || _busy ? null : _reserve,
      child: Text(soldOut ? 'Agotada' : (_busy ? 'Reservando…' : 'Reservar y pagar')),
    );
  }
}
