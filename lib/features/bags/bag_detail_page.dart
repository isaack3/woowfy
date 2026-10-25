import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/errors.dart';
import '../../core/analytics.dart';
import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../orders/countdown.dart';
import 'bag_image.dart';
import 'stars.dart';

class BagDetailPage extends StatelessWidget {
  const BagDetailPage({super.key, required this.bagId, this.resume = false});

  final String bagId;

  /// Vuelve del login después de tocar "Reservar": se destaca el botón para seguir con un toque.
  final bool resume;

  @override
  Widget build(BuildContext context) {
    return TrackView(
      event: 'bag_view',
      child: StreamBuilder<Bag?>(
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
                  IconButton(
                    tooltip: 'Compartir',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _share(context, bag),
                  ),
                ],
                const SizedBox(width: 4),
              ],
            ),
            body: snap.hasError || (snap.connectionState != ConnectionState.waiting && bag == null)
                ? const _GoneBag()
                : snap.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : _Detail(bag: bag!, resume: resume && FirebaseAuth.instance.currentUser != null),
          );
        },
      ),
    );
  }

  /// Comparte el enlace de la bolsa (WhatsApp, etc. con el menú nativo; si no existe, copia el enlace).
  Future<void> _share(BuildContext context, Bag bag) async {
    final url = 'https://app.woowfy.com/bag/${bag.id}';
    final text =
        '${bag.storeName} tiene una bolsa sorpresa a ${formatClp(bag.price)} '
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  fav
                      ? 'Dejaste de seguir a ${bag.storeName}'
                      : 'Sigues a ${bag.storeName}. Activa las notificaciones en Cuenta para saber cuando publique.',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.bag, this.resume = false});

  final Bag bag;
  final bool resume;

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    BagImage(url: bag.imageUrl, iconSize: 56),
                    Positioned(top: 12, left: 12, child: DiscountPill(bag.discountPercent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                StoreLogo(url: bag.storeLogoUrl, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bag.storeName, style: t.headlineSmall),
                      Row(
                        children: [
                          if (bag.category != null)
                            Text('${bag.category!}  ', style: t.bodySmall?.copyWith(color: WoowfyColors.muted)),
                          RatingBadge(avg: bag.storeRatingAvg, count: bag.storeRatingCount),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 16, color: WoowfyColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    [bag.address, bag.comuna, bag.region].where((s) => s.isNotEmpty).join(', '),
                    style: t.bodyMedium?.copyWith(color: WoowfyColors.muted),
                  ),
                ),
              ],
            ),
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
                    Row(
                      children: [
                        const Icon(Icons.schedule, color: WoowfyColors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Retiro ${formatPickup(bag.pickupStart, bag.pickupEnd)}',
                                style: t.titleMedium,
                              ),
                              Text(
                                'Muestra tu código QR en el local',
                                style: t.bodySmall?.copyWith(color: WoowfyColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(formatClp(bag.price), style: t.headlineMedium?.copyWith(color: WoowfyColors.green)),
                        const SizedBox(width: 10),
                        Text(
                          formatClp(bag.originalPrice),
                          style: t.titleMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: WoowfyColors.muted,
                          ),
                        ),
                        const Spacer(),
                        if (!bag.soldOut) Text('Quedan ${bag.quantityAvailable}', style: t.labelLarge),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!bag.soldOut) ...[const SizedBox(height: 12), const _Rules()],
            const SizedBox(height: 16),
            _PendingOr(bag: bag, child: resume && !bag.soldOut ? _ResumeReserve(bag: bag) : _ReserveButton(bag: bag)),
            if (!bag.soldOut) ...[const SizedBox(height: 8), const LegalNotice(prefix: 'Al reservar aceptas')],
            const _FeeSplit(),
            if (bag.storeRatingCount > 0) ...[const SizedBox(height: 24), _Reviews(storeId: bag.storeId)],
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

/// La bolsa ya no existe (se rescató, venció o el enlace es antiguo).
class _GoneBag extends StatelessWidget {
  const _GoneBag();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_bag_outlined, size: 48, color: WoowfyColors.green),
            const SizedBox(height: 12),
            Text('Esta bolsa ya se rescató o venció', style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Los locales publican bolsas nuevas todos los días.',
                style: t.bodyMedium?.copyWith(color: WoowfyColors.muted), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Ver bolsas disponibles')),
          ]),
        ),
      ),
    );
  }
}

/// Si la persona ya reservó esta bolsa y no ha pagado (p. ej. volvió atrás desde el pago), en vez de reservar otra
/// vez muestra la reserva vigente con su reloj y "Completar pago".
class _PendingOr extends StatelessWidget {
  const _PendingOr({required this.bag, required this.child});

  final Bag bag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchMyOrders(uid),
      builder: (context, snap) {
        final now = DateTime.now();
        final pending = (snap.data ?? const <BagOrder>[]).where((o) =>
            o.bagId == bag.id &&
            o.status == OrderStatus.pendingPayment &&
            o.expiresAt != null &&
            o.expiresAt!.isAfter(now));
        if (pending.isEmpty) return child;
        final order = pending.first;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: WoowfyColors.orangeSoft, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.timer_outlined, color: WoowfyColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text('Ya tienes esta bolsa reservada', style: Theme.of(context).textTheme.titleSmall)),
            ]),
            const SizedBox(height: 10),
            Countdown(
              until: order.expiresAt!,
              builder: (context, left) => FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: left == Duration.zero
                    ? null
                    : () => order.checkoutUrl != null
                        ? openCheckout(context, order.checkoutUrl!)
                        : context.go('/order/${order.id}'),
                child: Text(left == Duration.zero ? 'La reserva venció' : 'Completar pago · quedan ${formatMmSs(left)}'),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Después del login: "Listo, ya ingresaste" y el botón de reservar destacado (nada se reserva sin tocarlo).
class _ResumeReserve extends StatefulWidget {
  const _ResumeReserve({required this.bag});

  final Bag bag;

  @override
  State<_ResumeReserve> createState() => _ResumeReserveState();
}

class _ResumeReserveState extends State<_ResumeReserve> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _key.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: WoowfyColors.limeSoft, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.check_circle_outline, color: WoowfyColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text('Listo, ya ingresaste. Te queda un paso:', style: Theme.of(context).textTheme.titleSmall)),
        ]),
        const SizedBox(height: 10),
        _ReserveButton(bag: widget.bag),
      ]),
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
      context.go('/login?from=${Uri.encodeComponent('/bag/${widget.bag.id}?resume=1')}');
      return;
    }
    setState(() => _busy = true);
    Analytics.track('checkout_start');
    try {
      final order = await Repository.instance.createOrder(widget.bag.id);
      if (mounted) await openCheckout(context, order.checkoutUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, fallback: 'No pudimos reservar la bolsa. Intenta de nuevo.'))),
        );
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
      child: Text(soldOut ? 'Agotada' : (_busy ? 'Reservando…' : 'Reservar y pagar ${formatClp(widget.bag.price)}')),
    );
  }
}

/// Lo que afecta al cliente, dicho antes de pagar: reserva, cancelación y no retiro.
class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    Widget rule(IconData icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: WoowfyColors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: style)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(children: [
          rule(Icons.timer_outlined, ruleHold),
          rule(Icons.schedule, rulePickupWindow),
          rule(Icons.undo, ruleCancel),
          rule(Icons.gavel_outlined, ruleNoRetracto),
          rule(Icons.info_outline, ruleNoShow),
        ]),
      ),
    );
  }
}

/// Cómo se reparte el pago (plegable): transparente, pero sin competir con las reglas.
class _FeeSplit extends StatefulWidget {
  const _FeeSplit();

  @override
  State<_FeeSplit> createState() => _FeeSplitState();
}

class _FeeSplitState extends State<_FeeSplit> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted);
    return Column(children: [
      TextButton.icon(
        onPressed: () => setState(() => _open = !_open),
        icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
        label: const Text('¿Cómo se reparte lo que pagas?'),
      ),
      if (_open)
        Text(
          'El local recibe el $storeSharePercent del precio y Woowfy, una comisión de $platformFeePercent por la plataforma.',
          style: muted,
          textAlign: TextAlign.center,
        ),
    ]);
  }
}

/// Últimas opiniones del local.
class _Reviews extends StatelessWidget {
  const _Reviews({required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<Review>>(
      stream: Repository.instance.watchStoreReviews(storeId, limit: 5),
      builder: (context, snap) {
        final reviews = snap.data ?? const <Review>[];
        if (reviews.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opiniones', style: t.titleMedium),
            const SizedBox(height: 8),
            for (final r in reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Stars(value: r.rating.toDouble(), size: 16),
                            const SizedBox(width: 8),
                            Text(r.userName, style: t.labelLarge),
                          ],
                        ),
                        if (r.comment.isNotEmpty) ...[const SizedBox(height: 4), Text(r.comment)],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
