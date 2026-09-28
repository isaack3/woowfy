import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Navegación principal del cliente: barra inferior en móvil, riel lateral en pantallas anchas.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = [
    (path: '/', icon: Icons.shopping_bag_outlined, selected: Icons.shopping_bag, label: 'Bolsas'),
    (path: '/orders', icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Mis pedidos'),
    (path: '/account', icon: Icons.person_outline, selected: Icons.person, label: 'Cuenta'),
  ];

  int get _index {
    final i = _tabs.indexWhere((t) => t.path != '/' && location.startsWith(t.path));
    return i == -1 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    void go(int i) => context.go(_tabs[i].path);
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Image.asset('assets/brand/woowfy-isotipo.png', height: 34),
              ),
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: Text(t.label)),
              ],
            ),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: go,
        height: 68,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label),
        ],
      ),
    );
  }
}

/// Encabezado verde de las pantallas principales (continúa el AppBar con un título y subtítulo).
class GreenHeader extends StatelessWidget {
  const GreenHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: WoowfyColors.green,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
      child: Center(
        child: ConstrainedBox(
          // Ancho fijo (hasta 1100) para que el título quede alineado a la izquierda del contenido.
          constraints: const BoxConstraints(maxWidth: 1100, minWidth: double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.headlineMedium?.copyWith(color: WoowfyColors.cream)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: t.bodyLarge?.copyWith(color: WoowfyColors.lime, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
