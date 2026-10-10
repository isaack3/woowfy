import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'email_settings_tab.dart';
import 'analytics_tab.dart';
import 'payouts_tab.dart';
import 'sales_tab.dart';
import 'stores_tabs.dart';
import 'users_tab.dart';
import 'waitlist_tab.dart';

/// Panel interno de Woowfy. Solo para usuarios con `role: admin` en `users/{uid}`
/// (las reglas de Firestore también lo exigen, esto es solo la puerta de la UI).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key, this.tab});

  /// Pestaña inicial, desde la URL (/admin?tab=pagos).
  final String? tab;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  // Se guarda: al cambiar de pestaña cambia la URL y no debe volver a cargarse el permiso (ni parpadear).
  late final Stream<String?> _role = Repository.instance.watchRole(FirebaseAuth.instance.currentUser!.uid);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _role,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data != 'admin') return const _NoAccess();
        return _AdminShell(tab: widget.tab);
      },
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/'))),
      body: const Center(child: Text('No tienes acceso a esta sección.')),
    );
  }
}

typedef _AdminTab = ({String slug, String label, IconData icon, String info, Widget child});

const List<_AdminTab> _tabs = [
  (
    slug: 'solicitudes',
    label: 'Solicitudes',
    icon: Icons.storefront_outlined,
    info: 'Locales que pidieron sumarse a Woowfy. Revisa sus datos y apruébalos para que puedan publicar bolsas, o recházalos indicando el motivo.',
    child: PendingStoresTab(),
  ),
  (
    slug: 'comercios',
    label: 'Comercios',
    icon: Icons.store_outlined,
    info: 'Locales ya revisados: aprobados, suspendidos o rechazados. Desde aquí los suspendes o reactivas.',
    child: StoresTab(),
  ),
  (
    slug: 'pagos',
    label: 'Pagos',
    icon: Icons.payments_outlined,
    info: 'Lo que Woowfy le debe a cada local (también a los suspendidos), "Liquidar todos" y el historial de liquidaciones con su planilla.',
    child: PayoutsTab(),
  ),
  (
    slug: 'ventas',
    label: 'Ventas',
    icon: Icons.insights_outlined,
    info: 'Resumen de pedidos de toda la plataforma: bolsas vendidas, ventas totales y la comisión de Woowfy en el periodo elegido.',
    child: SalesTab(),
  ),
  (
    slug: 'analitica',
    label: 'Analítica',
    icon: Icons.query_stats,
    info: 'Visitas a woowfy.com y a la app, y el camino hasta la compra: cuántos ven una bolsa, reservan, pagan y retiran. Anónima: sin cookies ni datos personales.',
    child: AnalyticsTab(),
  ),
  (
    slug: 'interesados',
    label: 'Interesados',
    icon: Icons.mark_email_unread_outlined,
    info: 'Personas y locales inscritos en la lista de espera de woowfy.com. Puedes buscarlos, copiar sus correos o exportarlos, y borrar los datos de quien lo pida.',
    child: WaitlistTab(),
  ),
  (
    slug: 'usuarios',
    label: 'Usuarios',
    icon: Icons.group_outlined,
    info: 'Cuentas registradas en la app. Desde aquí das o quitas permisos de administrador.',
    child: UsersTab(),
  ),
  (
    slug: 'correo',
    label: 'Correo',
    icon: Icons.alternate_email,
    info: 'Remitente y correo de respuesta de los mensajes automáticos (bienvenida a la lista de espera y otros avisos).',
    child: EmailSettingsTab(),
  ),
];

/// Pestañas con su propia URL (/admin?tab=pagos): se pueden guardar o compartir.
class _AdminShell extends StatefulWidget {
  const _AdminShell({this.tab});

  final String? tab;

  @override
  State<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<_AdminShell> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: _tabs.length,
    vsync: this,
    initialIndex: math.max(0, _tabs.indexWhere((t) => t.slug == widget.tab)),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.indexIsChanging) return;
      final slug = _tabs[_controller.index].slug;
      if (slug != widget.tab) context.replace('/admin?tab=$slug');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Woowfy · Admin'),
        leading: BackButton(onPressed: () => context.go('/')),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final t in _tabs)
              t.slug == 'solicitudes'
                  ? Tab(
                      child: StreamBuilder<List<Store>>(
                        stream: Repository.instance.watchStoresByStatus(StoreStatus.pending),
                        builder: (context, snap) {
                          final n = snap.data?.length ?? 0;
                          return Badge(
                            isLabelVisible: n > 0,
                            label: Text('$n'),
                            offset: const Offset(14, -4),
                            child: Text(t.label),
                          );
                        },
                      ),
                    )
                  : Tab(text: t.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [for (final t in _tabs) _Section(slug: t.slug, icon: t.icon, info: t.info, child: t.child)],
      ),
    );
  }
}

/// Contenido de una pestaña: centrado con ancho máximo y una breve explicación arriba, que se puede cerrar
/// (queda cerrada en este navegador).
class _Section extends StatefulWidget {
  const _Section({required this.slug, required this.icon, required this.info, required this.child});

  final String slug;
  final IconData icon;
  final String info;
  final Widget child;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _hidden = false;

  String get _key => 'admin.help.${widget.slug}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted && (p.getBool(_key) ?? false)) setState(() => _hidden = true);
    }).catchError((_) {});
  }

  Future<void> _hide() async {
    setState(() => _hidden = true);
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            if (!_hidden)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  decoration: BoxDecoration(
                    color: WoowfyColors.limeSoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(widget.icon, size: 20, color: WoowfyColors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.info,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: WoowfyColors.green, height: 1.35),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ocultar esta ayuda',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18, color: WoowfyColors.green),
                        onPressed: _hide,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }
}
