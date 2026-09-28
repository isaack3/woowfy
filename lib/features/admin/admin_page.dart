import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import 'sales_tab.dart';
import 'stores_tabs.dart';

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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Woowfy · Admin'),
          leading: BackButton(onPressed: () => context.go('/')),
          bottom: TabBar(
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
            ],
          ),
        ),
        body: const TabBarView(
          children: [PendingStoresTab(), StoresTab(), SalesTab()],
        ),
      ),
    );
  }
}
