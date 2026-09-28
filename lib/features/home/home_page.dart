import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_card.dart';
import '../shell/app_shell.dart';
import 'bags_map.dart';

enum _Sort {
  soonest('Retiro más próximo'),
  nearest('Más cerca'),
  cheapest('Menor precio'),
  discount('Mayor descuento');

  const _Sort(this.label);
  final String label;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _bags = Repository.instance.watchAvailableBags();
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<Set<String>> _favorites = _uid == null
      ? Stream.value(<String>{})
      : Repository.instance.watchFavoriteStoreIds(_uid);
  String? _category;
  bool _pickupNow = false;
  bool _favoritesOnly = false;
  bool _map = false;
  _Sort _sort = _Sort.soonest;
  LatLng? _me;
  bool _locating = false;

  /// Pide la ubicación (una vez). Devuelve false si el usuario no la entrega.
  Future<bool> _locate() async {
    if (_me != null) return true;
    setState(() => _locating = true);
    final me = await currentPosition();
    if (!mounted) return false;
    setState(() {
      _me = me;
      _locating = false;
    });
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos obtener tu ubicación. Revisa el permiso de ubicación del navegador.',
          ),
        ),
      );
    }
    return me != null;
  }

  Future<void> _setSort(_Sort sort) async {
    if (sort == _Sort.nearest && !await _locate()) return;
    setState(() => _sort = sort);
  }

  Future<void> _toggleMap() async {
    setState(() => _map = !_map);
    if (_map) await _locate();
  }

  Map<String, double> _distances(List<Bag> bags) => {
    if (_me != null)
      for (final b in bags)
        if (b.hasLocation) b.id: distanceMeters(_me!, b.lat!, b.lng!),
  };

  List<Bag> _apply(
    List<Bag> all,
    Set<String> favorites,
    Map<String, double> distances,
  ) {
    final list = all.where((b) {
      if (_favoritesOnly && !favorites.contains(b.storeId)) return false;
      if (_category != null && b.category != _category) return false;
      if (_pickupNow && !b.pickupNow) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.soonest:
        list.sort((a, b) => a.pickupEnd.compareTo(b.pickupEnd));
      case _Sort.nearest:
        list.sort(
          (a, b) => (distances[a.id] ?? double.infinity).compareTo(
            distances[b.id] ?? double.infinity,
          ),
        );
      case _Sort.cheapest:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _Sort.discount:
        list.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    }
    // Las agotadas al final.
    list.sort((a, b) => (a.soldOut ? 1 : 0).compareTo(b.soldOut ? 1 : 0));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const WoowfyLogo(onDark: true)),
      body: StreamBuilder<Set<String>>(
        stream: _favorites,
        builder: (context, favSnap) => StreamBuilder<List<Bag>>(
          stream: _bags,
          builder: (context, snap) {
            final favorites = favSnap.data ?? const <String>{};
            final all = snap.data;
            final distances = all == null
                ? const <String, double>{}
                : _distances(all);
            final bags = all == null ? null : _apply(all, favorites, distances);
            final filtered = _category != null || _pickupNow || _favoritesOnly;
            final subtitle = all == null
                ? 'Todo Chile'
                : '${all.length} ${all.length == 1 ? 'bolsa disponible' : 'bolsas disponibles'} · todo Chile';
            // Solo se ofrecen las categorías que tienen bolsas hoy (más la elegida, para poder quitarla).
            final categories =
                {
                  ...?all?.map((b) => b.category).whereType<String>(),
                  ?_category,
                }.toList()..sort(
                  (a, b) => storeCategories
                      .indexOf(a)
                      .compareTo(storeCategories.indexOf(b)),
                );

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: GreenHeader(
                    title: 'Bolsas de hoy',
                    subtitle: subtitle,
                  ),
                ),
                if (all != null && all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _Filters(
                      categories: categories,
                      category: _category,
                      pickupNow: _pickupNow,
                      favoritesOnly: _favoritesOnly,
                      showFavorites: _uid != null,
                      sort: _sort,
                      map: _map,
                      locating: _locating,
                      onCategory: (c) => setState(() => _category = c),
                      onPickupNow: (v) => setState(() => _pickupNow = v),
                      onFavorites: (v) => setState(() => _favoritesOnly = v),
                      onSort: _setSort,
                      onToggleMap: _toggleMap,
                    ),
                  ),
                if (snap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Message(
                      icon: Icons.cloud_off,
                      text: 'No pudimos cargar las bolsas.\n${snap.error}',
                    ),
                  )
                else if (bags == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (bags.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: filtered
                        ? _Message(
                            icon: Icons.filter_alt_off_outlined,
                            text: _favoritesOnly && favorites.isEmpty
                                ? 'Aún no tienes locales favoritos. Toca el corazón en una bolsa para seguir al local.'
                                : 'No hay bolsas con estos filtros.',
                            action: TextButton(
                              onPressed: () => setState(() {
                                _category = null;
                                _pickupNow = false;
                                _favoritesOnly = false;
                              }),
                              child: const Text('Quitar filtros'),
                            ),
                          )
                        : const _Message(
                            icon: Icons.eco_outlined,
                            text:
                                'Hoy no hay bolsas disponibles.\nLos locales publican durante el día: vuelve más tarde.',
                          ),
                  )
                else if (_map)
                  SliverFillRemaining(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BagsMap(
                          bags: bags,
                          me: _me,
                          distances: distances,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverCrossAxisConstrained(
                      maxCrossAxisExtent: 1100,
                      child: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 360,
                              mainAxisExtent: 284,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: bags.length,
                        itemBuilder: (context, i) {
                          final d = distances[bags[i].id];
                          return BagCard(
                            bag: bags[i],
                            distance: d == null ? null : formatDistance(d),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.categories,
    required this.category,
    required this.pickupNow,
    required this.favoritesOnly,
    required this.showFavorites,
    required this.sort,
    required this.map,
    required this.locating,
    required this.onCategory,
    required this.onPickupNow,
    required this.onFavorites,
    required this.onSort,
    required this.onToggleMap,
  });

  final List<String> categories;
  final String? category;
  final bool pickupNow;
  final bool favoritesOnly;
  final bool showFavorites;
  final _Sort sort;
  final bool map;
  final bool locating;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onPickupNow;
  final ValueChanged<bool> onFavorites;
  final ValueChanged<_Sort> onSort;
  final VoidCallback onToggleMap;

  @override
  Widget build(BuildContext context) {
    Widget chip(
      String label,
      bool selected,
      VoidCallback onTap, {
      IconData? icon,
    }) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        avatar: icon == null
            ? null
            : Icon(icon, size: 16, color: WoowfyColors.green),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: WoowfyColors.lime,
        backgroundColor: Colors.white,
        side: const BorderSide(color: WoowfyColors.line),
        onSelected: (_) => onTap(),
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      chip(
                        'Retiro ahora',
                        pickupNow,
                        () => onPickupNow(!pickupNow),
                        icon: Icons.bolt,
                      ),
                      if (showFavorites)
                        chip(
                          'Favoritos',
                          favoritesOnly,
                          () => onFavorites(!favoritesOnly),
                          icon: Icons.favorite_border,
                        ),
                      chip('Todas', category == null, () => onCategory(null)),
                      for (final c in categories)
                        chip(
                          c,
                          category == c,
                          () => onCategory(category == c ? null : c),
                        ),
                    ],
                  ),
                ),
              ),
              if (locating)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                tooltip: map ? 'Ver lista' : 'Ver mapa',
                icon: Icon(
                  map ? Icons.view_agenda_outlined : Icons.map_outlined,
                  color: WoowfyColors.green,
                ),
                onPressed: onToggleMap,
              ),
              PopupMenuButton<_Sort>(
                tooltip: 'Ordenar',
                icon: const Icon(Icons.sort, color: WoowfyColors.green),
                initialValue: sort,
                onSelected: onSort,
                itemBuilder: (_) => [
                  for (final s in _Sort.values)
                    PopupMenuItem(value: s, child: Text(s.label)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centra un sliver con ancho máximo (grilla legible en pantallas grandes).
class SliverCrossAxisConstrained extends StatelessWidget {
  const SliverCrossAxisConstrained({
    super.key,
    required this.maxCrossAxisExtent,
    required this.child,
  });

  final double maxCrossAxisExtent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.crossAxisExtent - maxCrossAxisExtent;
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: extra > 0 ? extra / 2 : 0),
          sliver: child,
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: WoowfyColors.green.withValues(alpha: .5),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
