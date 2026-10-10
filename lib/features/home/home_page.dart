import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/chile.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_card.dart';
import '../shell/app_shell.dart';
import 'bags_map.dart';
import 'waitlist_form.dart';

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

/// Clave donde se recuerda la región elegida (en el navegador o el teléfono).
const _regionKey = 'home.region';

const _merchantsGuideUrl = 'https://woowfy.com/merchants';

class _HomePageState extends State<HomePage> {
  Stream<List<Bag>> _bags = Repository.instance.watchAvailableBags();
  final _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<Set<String>> _favorites = _uid == null
      ? Stream.value(<String>{})
      : Repository.instance.watchFavoriteStoreIds(_uid);
  String? _category;
  /// Región elegida; null = todo Chile.
  String? _region;
  bool _pickupNow = false;
  bool _favoritesOnly = false;
  bool _map = false;
  _Sort _sort = _Sort.soonest;
  LatLng? _me;
  bool _locating = false;

  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _loadRegion();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadRegion() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_regionKey);
      if (saved != null && chileRegions.contains(saved) && mounted) setState(() => _region = saved);
    } catch (_) {
      // Sin almacenamiento (p. ej. navegación privada): se parte en todo Chile.
    }
  }

  Future<void> _setRegion(String? region) async {
    setState(() => _region = region);
    try {
      final prefs = await SharedPreferences.getInstance();
      region == null ? await prefs.remove(_regionKey) : await prefs.setString(_regionKey, region);
    } catch (e) {
      debugPrint('No se pudo guardar la región: $e');
    }
  }

  /// Pide la ubicación (una vez), explicando antes para qué. Devuelve false si el usuario no la entrega.
  Future<bool> _locate() async {
    if (_me != null) return true;
    if (!await locationGranted()) {
      if (!mounted) return false;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Usar tu ubicación'),
          content: const Text('La usamos solo en este momento para ordenar las bolsas por cercanía y mostrarte en el mapa. '
              'No la guardamos.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ahora no')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
          ],
        ),
      );
      if (ok != true) return false;
    }
    if (!mounted) return false;
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
            'No pudimos obtener tu ubicación. Revisa el permiso de ubicación del navegador, o elige tu región.',
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

  Future<void> _setMap(bool map) async {
    setState(() => _map = map);
    // En el mapa la ubicación es un extra: solo se usa si ya hay permiso (no se pide de nuevo).
    if (map && _me == null && await locationGranted()) await _locate();
  }

  Future<void> _pickRegion(List<Bag> all) async {
    final counts = <String, int>{};
    for (final b in all.where((b) => !b.soldOut)) {
      counts[b.region] = (counts[b.region] ?? 0) + 1;
    }
    final picked = await showModalBottomSheet<_RegionChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _RegionSheet(selected: _region, counts: counts, total: all.where((b) => !b.soldOut).length),
    );
    if (picked == null) return;
    if (picked.nearMe) {
      if (!await _locate()) return;
      await _setRegion(null);
      await _setSort(_Sort.nearest);
    } else {
      await _setRegion(picked.region);
    }
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
      if (_region != null && b.region != _region) return false;
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
            // La consulta fija "ahora" al suscribirse: aquí se descartan las que cerraron mientras la página seguía abierta.
            final now = DateTime.now();
            final all = snap.data?.where((b) => b.pickupEnd.isAfter(now)).toList();
            final distances = all == null
                ? const <String, double>{}
                : _distances(all);
            final bags = all == null ? null : _apply(all, favorites, distances);
            final inRegion = all?.where((b) => _region == null || b.region == _region).toList();
            final filtered = _category != null || _pickupNow || _favoritesOnly;
            final place = _region ?? 'todo Chile';
            final available = inRegion?.where((b) => !b.soldOut).length;
            final subtitle = available == null
                ? (_region ?? 'Todo Chile')
                : available == 0
                    ? 'Aún sin bolsas · $place'
                    : '$available ${available == 1 ? 'bolsa disponible' : 'bolsas disponibles'} · $place';
            // Solo se ofrecen las categorías que tienen bolsas hoy en la zona (más la elegida, para poder quitarla).
            final categories =
                {
                  ...?inRegion?.map((b) => b.category).whereType<String>(),
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
                    // Con 0 bolsas el título no promete lo que no hay.
                    title: available == 0 ? 'Rescata comida en todo Chile' : 'Bolsas disponibles',
                    subtitle: subtitle,
                  ),
                ),
                if (all != null)
                  SliverToBoxAdapter(
                    child: _Filters(
                      // Con 0 bolsas solo queda "dónde": orden y mapa no sirven todavía.
                      onlyRegion: all.isEmpty,
                      region: _region,
                      nearMe: _region == null && _sort == _Sort.nearest,
                      categories: categories,
                      category: _category,
                      pickupNow: _pickupNow,
                      favoritesOnly: _favoritesOnly,
                      showFavorites: _uid != null,
                      showCategories: inRegion!.isNotEmpty,
                      sort: _sort,
                      map: _map,
                      locating: _locating,
                      onRegion: () => _pickRegion(all),
                      onCategory: (c) => setState(() => _category = c),
                      onPickupNow: (v) => setState(() => _pickupNow = v),
                      onFavorites: (v) => setState(() => _favoritesOnly = v),
                      onSort: _setSort,
                      onMap: _setMap,
                    ),
                  ),
                if (snap.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorRetry(
                      title: 'No pudimos cargar las bolsas',
                      error: snap.error,
                      onRetry: () => setState(() => _bags = Repository.instance.watchAvailableBags()),
                    ),
                  )
                else if (bags == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (inRegion!.isEmpty)
                  SliverToBoxAdapter(
                    child: _EmptyHome(
                      region: _region,
                      onAllChile: all!.isEmpty ? null : () => _setRegion(null),
                    ),
                  )
                else if (bags.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Message(
                      icon: Icons.filter_alt_off_outlined,
                      text: _favoritesOnly && favorites.isEmpty
                          ? 'Aún no tienes locales favoritos. En el detalle de una bolsa, toca el corazón para seguir al local.'
                          : filtered
                              ? 'No hay bolsas con estos filtros.'
                              : 'No hay bolsas disponibles por ahora.',
                      action: filtered
                          ? TextButton(
                              onPressed: () => setState(() {
                                _category = null;
                                _pickupNow = false;
                                _favoritesOnly = false;
                              }),
                              child: const Text('Quitar filtros'),
                            )
                          : null,
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
                            SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 360,
                              mainAxisExtent: 304 + _extraCardHeight(context),
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

/// Alto extra de la tarjeta cuando la persona usa letra más grande en el navegador o el teléfono.
double _extraCardHeight(BuildContext context) =>
    ((MediaQuery.textScalerOf(context).scale(100) / 100 - 1).clamp(0.0, 2.0)) * 90;

/// Dos filas: arriba dónde, cómo se ordena y cómo se ve (lista o mapa); abajo los filtros.
class _Filters extends StatelessWidget {
  const _Filters({
    this.onlyRegion = false,
    this.nearMe = false,
    required this.region,
    required this.categories,
    required this.category,
    required this.pickupNow,
    required this.favoritesOnly,
    required this.showFavorites,
    required this.showCategories,
    required this.sort,
    required this.map,
    required this.locating,
    required this.onRegion,
    required this.onCategory,
    required this.onPickupNow,
    required this.onFavorites,
    required this.onSort,
    required this.onMap,
  });

  final bool onlyRegion;

  /// "Cerca de ti": todo Chile ordenado por cercanía.
  final bool nearMe;
  final String? region;
  final List<String> categories;
  final String? category;
  final bool pickupNow;
  final bool favoritesOnly;
  final bool showFavorites;
  final bool showCategories;
  final _Sort sort;
  final bool map;
  final bool locating;
  final VoidCallback onRegion;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onPickupNow;
  final ValueChanged<bool> onFavorites;
  final ValueChanged<_Sort> onSort;
  final ValueChanged<bool> onMap;

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

    // Botón tipo "pastilla" con valor visible y flecha (abre una lista).
    Widget picker(IconData icon, String label, {bool active = false}) => Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: ShapeDecoration(
            color: active ? WoowfyColors.lime : Colors.white,
            shape: const StadiumBorder(side: BorderSide(color: WoowfyColors.line)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: WoowfyColors.green),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: WoowfyColors.green),
          ]),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: 'Zona: ${nearMe ? 'Cerca de ti' : region ?? 'Todo Chile'}. Cambiar',
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: onRegion,
                      child: picker(
                        nearMe ? Icons.my_location : Icons.place_outlined,
                        nearMe ? 'Cerca de ti' : region ?? 'Todo Chile',
                        active: region != null || nearMe,
                      ),
                    ),
                  ),
                  if (!onlyRegion) PopupMenuButton<_Sort>(
                    tooltip: 'Ordenar',
                    initialValue: sort,
                    onSelected: onSort,
                    itemBuilder: (_) => [
                      for (final s in _Sort.values)
                        PopupMenuItem(value: s, child: Text(s.label)),
                    ],
                    child: picker(Icons.sort, sort.label),
                  ),
                  if (locating && !onlyRegion)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (!onlyRegion) SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Lista'), icon: Icon(Icons.view_agenda_outlined, size: 16)),
                      ButtonSegment(value: true, label: Text('Mapa'), icon: Icon(Icons.map_outlined, size: 16)),
                    ],
                    selected: {map},
                    onSelectionChanged: (v) => onMap(v.first),
                  ),
                ],
              ),
              if (showCategories) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
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
                          icon: favoritesOnly ? Icons.favorite : Icons.favorite_border,
                        ),
                      Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.only(right: 8),
                        color: WoowfyColors.line,
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RegionChoice {
  const _RegionChoice({this.region, this.nearMe = false});

  final String? region;
  final bool nearMe;
}

/// Lista de "Todo Chile" + las 16 regiones con cuántas bolsas hay hoy, y la opción de usar la ubicación.
class _RegionSheet extends StatelessWidget {
  const _RegionSheet({required this.selected, required this.counts, required this.total});

  final String? selected;
  final Map<String, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = t.bodySmall?.copyWith(color: WoowfyColors.muted);
    Widget option(String label, String? value, int count) => ListTile(
          selected: selected == value,
          selectedTileColor: WoowfyColors.limeSoft,
          selectedColor: WoowfyColors.green,
          leading: Icon(selected == value ? Icons.check : null, color: WoowfyColors.green),
          title: Text(label),
          trailing: Text(count == 1 ? '1 bolsa' : '$count bolsas', style: muted),
          onTap: () => Navigator.pop(context, _RegionChoice(region: value)),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('¿Dónde quieres rescatar?', style: t.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.my_location, color: WoowfyColors.green),
            title: const Text('Usar mi ubicación'),
            subtitle: const Text('Todo Chile, ordenado por cercanía'),
            onTap: () => Navigator.pop(context, const _RegionChoice(nearMe: true)),
          ),
          const Divider(),
          option('Todo Chile', null, total),
          for (final r in chileRegions) option(r, r, counts[r] ?? 0),
        ],
      ),
    );
  }
}

/// Sin bolsas (en todo Chile o en la región elegida): explica cómo funciona, deja avisarse e invita a los locales.
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.region, this.onAllChile});

  final String? region;

  /// Solo cuando hay bolsas en otras regiones.
  final VoidCallback? onAllChile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: WoowfyColors.limeSoft,
              child: Text(n, style: const TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: t.bodyLarge)),
          ]),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                region == null ? 'Aún no hay bolsas publicadas' : 'Sé de los primeros en $region',
                style: t.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Los locales publican durante el día lo que no vendieron. Así funciona:',
                style: t.bodyMedium?.copyWith(color: WoowfyColors.muted),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(children: [
                    step('1', 'Reservas una bolsa sorpresa a mitad de precio.'),
                    step('2', 'Pagas en línea, sin instalar nada.'),
                    step('3', 'La retiras en el local mostrando tu QR.'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              if (onAllChile != null) ...[
                OutlinedButton(onPressed: onAllChile, child: const Text('Ver bolsas de todo Chile')),
                const SizedBox(height: 16),
              ],
              // El aviso se pide aquí mismo (antes llevaba a woowfy.com y se perdía el contexto).
              WaitlistForm(region: region),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('¿Tienes un local?', style: t.bodyMedium?.copyWith(color: WoowfyColors.muted)),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(_merchantsGuideUrl)),
                    child: const Text('Publica tus bolsas'),
                  ),
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
