import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../bags/bag_card.dart';

/// Mapa (OpenStreetMap) con las bolsas disponibles; al tocar un precio se abre la tarjeta.
class BagsMap extends StatelessWidget {
  const BagsMap({super.key, required this.bags, this.me, this.distances = const {}});

  final List<Bag> bags;
  final LatLng? me;
  final Map<String, double> distances;

  @override
  Widget build(BuildContext context) {
    final located = bags.where((b) => b.hasLocation).toList();
    final center = me ?? (located.isNotEmpty ? LatLng(located.first.lat!, located.first.lng!) : santiago);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: me != null ? 13 : 11, minZoom: 4, maxZoom: 18),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.woowfy.woowfy',
        ),
        MarkerLayer(markers: [
          if (me != null)
            Marker(
              point: me!,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2F80ED),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
              ),
            ),
          for (final b in located)
            Marker(
              point: LatLng(b.lat!, b.lng!),
              width: 86,
              height: 36,
              child: GestureDetector(
                onTap: () => _open(context, b),
                child: Container(
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: b.soldOut ? WoowfyColors.line : WoowfyColors.lime,
                    shape: const StadiumBorder(side: BorderSide(color: WoowfyColors.green, width: 2)),
                    shadows: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                  ),
                  child: Text(
                    formatClp(b.price),
                    style: const TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
              ),
            ),
        ]),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap', onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'))),
          ],
        ),
      ],
    );
  }

  void _open(BuildContext context, Bag bag) {
    final d = distances[bag.id];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SizedBox(height: 290, child: BagCard(bag: bag, distance: d == null ? null : formatDistance(d))),
          ),
        ),
      ),
    );
  }
}
