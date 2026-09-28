import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _comuna;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('woowfy', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton(onPressed: () => context.go('/comercio'), child: const Text('Soy comercio')),
          if (user == null)
            TextButton(onPressed: () => context.go('/ingresar'), child: const Text('Ingresar'))
          else ...[
            StreamBuilder<String?>(
              stream: Repository.instance.watchRole(user.uid),
              builder: (context, snap) => snap.data == 'admin'
                  ? TextButton(onPressed: () => context.go('/admin'), child: const Text('Admin'))
                  : const SizedBox.shrink(),
            ),
            TextButton(onPressed: () => context.go('/pedidos'), child: const Text('Mis pedidos')),
            IconButton(
              tooltip: 'Cerrar sesión',
              icon: const Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                sliver: SliverToBoxAdapter(child: _Header()),
              ),
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: _comuna == null,
                        onSelected: (_) => setState(() => _comuna = null),
                      ),
                      for (final c in pilotComunas)
                        ChoiceChip(
                          label: Text(c),
                          selected: _comuna == c,
                          onSelected: (_) => setState(() => _comuna = c),
                        ),
                    ],
                  ),
                ),
              ),
              StreamBuilder<List<Bag>>(
                stream: Repository.instance.watchAvailableBags(comuna: _comuna),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No pudimos cargar las bolsas.\n${snap.error}')),
                    );
                  }
                  if (!snap.hasData) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final bags = snap.data!;
                  if (bags.isEmpty) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Hoy no hay bolsas disponibles en esta zona.\nVuelve más tarde 🌱',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 360,
                        mainAxisExtent: 250,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: bags.length,
                      itemBuilder: (context, i) => BagCard(bag: bags[i]),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rescata comida rica a mitad de precio', style: t.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Bolsas sorpresa de locales cerca de ti. Tú ahorras y evitamos que la comida se bote.',
          style: t.bodyLarge,
        ),
      ],
    );
  }
}
