import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'email_settings_tab.dart';
import 'sales_tab.dart';
import 'stores_tabs.dart';
import 'users_tab.dart';
import 'waitlist_tab.dart';

/// Panel interno de Woowfy. Solo para usuarios con `role: admin` en `users/{uid}`
/// (las reglas de Firestore también lo exigen, esto es solo la puerta de la UI).
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<String?>(
      stream: Repository.instance.watchRole(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.data != 'admin') return const _NoAccess();
        return const _AdminShell();
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

class _AdminShell extends StatelessWidget {
  const _AdminShell();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Woowfy · Admin'),
          leading: BackButton(onPressed: () => context.go('/')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                child: StreamBuilder<List<Store>>(
                  stream: Repository.instance.watchStoresByStatus(StoreStatus.pending),
                  builder: (context, snap) {
                    final n = snap.data?.length ?? 0;
                    return Badge(
                      isLabelVisible: n > 0,
                      label: Text('$n'),
                      offset: const Offset(14, -4),
                      child: const Text('Solicitudes'),
                    );
                  },
                ),
              ),
              const Tab(text: 'Comercios'),
              const Tab(text: 'Ventas'),
              const Tab(text: 'Interesados'),
              const Tab(text: 'Usuarios'),
              const Tab(text: 'Correo'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _Section(
              icon: Icons.storefront_outlined,
              info: 'Locales que pidieron sumarse a Woowfy. Revisa sus datos y apruébalos para que puedan publicar bolsas, o recházalos indicando el motivo.',
              child: PendingStoresTab(),
            ),
            _Section(
              icon: Icons.store_outlined,
              info: 'Locales ya revisados: aprobados, suspendidos o rechazados. Con “Liquidar” registras el pago de sus ventas retiradas.',
              child: StoresTab(),
            ),
            _Section(
              icon: Icons.insights_outlined,
              info: 'Resumen de pedidos de toda la plataforma: bolsas vendidas, ventas totales y la comisión de Woowfy en el periodo elegido.',
              child: SalesTab(),
            ),
            _Section(
              icon: Icons.mark_email_unread_outlined,
              info: 'Personas y locales que se inscribieron en la lista de espera de woowfy.com. Puedes copiar sus correos o exportarlos.',
              child: WaitlistTab(),
            ),
            _Section(
              icon: Icons.group_outlined,
              info: 'Cuentas registradas en la app. Desde aquí das o quitas permisos de administrador.',
              child: UsersTab(),
            ),
            _Section(
              icon: Icons.alternate_email,
              info: 'Remitente y correo de respuesta de los mensajes automáticos (bienvenida a la lista de espera y otros avisos).',
              child: EmailSettingsTab(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenido de una pestaña: centrado con ancho máximo y una breve explicación arriba.
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.info, required this.child});

  final IconData icon;
  final String info;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: WoowfyColors.limeSoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: WoowfyColors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        info,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: WoowfyColors.green, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
