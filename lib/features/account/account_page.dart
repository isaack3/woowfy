import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/repository.dart';
import '../shell/app_shell.dart';
import 'account_extras.dart';

/// Cuenta del usuario: datos, acceso al panel del comercio y al admin, cerrar sesión.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        return Scaffold(
          appBar: AppBar(title: const WoowfyLogo(onDark: true)),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              GreenHeader(
                title: user == null ? 'Tu cuenta' : 'Hola, ${_firstName(user)}',
                subtitle: user?.email,
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (user != null) ...[
                          ImpactCard(uid: user.uid),
                          const SizedBox(height: 16),
                        ],
                        user == null
                            ? const _SignedOut()
                            : _SignedIn(user: user),
                        const SizedBox(height: 16),
                        AppSettingsCard(uid: user?.uid),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => launchUrl(Uri.parse(termsUrl)),
                              child: const Text('Términos y condiciones'),
                            ),
                            TextButton(
                              onPressed: () => launchUrl(Uri.parse(privacyUrl)),
                              child: const Text('Política de privacidad'),
                            ),
                          ],
                        ),
                        Center(
                          child: TextButton(
                            onPressed: () => launchUrl(Uri.parse(passvaUrl)),
                            style: TextButton.styleFrom(foregroundColor: WoowfyColors.muted),
                            child: const Text('Un producto de Passva'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _firstName(User user) {
    final name = (user.displayName ?? '').trim();
    // Sin emojis: en web obligan a descargar una fuente extra y el texto queda en blanco mientras carga.
    return name.isEmpty
        ? (user.email ?? '').split('@').first
        : name.split(RegExp(r'\s+')).first;
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Image.asset('assets/brand/woowfy-isotipo.png', height: 72),
            const SizedBox(height: 12),
            Text(
              'Ingresa para reservar bolsas y ver tus pedidos.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/login?from=%2Faccount'),
              child: const Text('Ingresar o crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(
              Icons.badge_outlined,
              color: WoowfyColors.green,
            ),
            title: const Text('Tu nombre'),
            subtitle: Text(
              (user.displayName ?? '').isEmpty
                  ? 'Agrega tu nombre'
                  : user.displayName!,
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _editName(context, user),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.receipt_long_outlined,
              color: WoowfyColors.green,
            ),
            title: const Text('Mis pedidos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/orders'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(
              Icons.storefront_outlined,
              color: WoowfyColors.green,
            ),
            title: const Text('Mi local'),
            subtitle: const Text('Publica bolsas y valida retiros'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/merchant'),
          ),
          StreamBuilder<String?>(
            stream: Repository.instance.watchRole(user.uid),
            builder: (context, snap) => snap.data != 'admin'
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.admin_panel_settings_outlined,
                          color: WoowfyColors.green,
                        ),
                        title: const Text('Panel admin'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/admin'),
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: WoowfyColors.coral),
            title: const Text('Cerrar sesión'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/');
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.person_remove_outlined, color: Theme.of(context).colorScheme.error),
            title: const Text('Eliminar mi cuenta'),
            subtitle: const Text('Borra tus datos personales de Woowfy'),
            onTap: () => _deleteAccount(context),
          ),
        ],
      ),
    );
  }
}

/// Derecho de supresión: confirma y elimina la cuenta en el servidor (que borra perfil, favoritos y acceso).
Future<void> _deleteAccount(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Eliminar mi cuenta'),
      content: const Text(
        'Se borrarán tu perfil, tus locales favoritos, tus avisos y tu acceso a Woowfy. Tus reservas sin pagar se '
        'cancelan. Tus compras pasadas se conservan sin tu nombre ni correo, porque la ley tributaria nos obliga a '
        'guardarlas.\n\nEsto no se puede deshacer.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eliminar mi cuenta'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  messenger.showSnackBar(const SnackBar(content: Text('Eliminando tu cuenta…')));
  try {
    await Repository.instance.deleteAccount();
    await FirebaseAuth.instance.signOut();
    router.go('/');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Tu cuenta y tus datos personales fueron eliminados.')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(friendlyError(e, fallback: 'No pudimos eliminar tu cuenta. Intenta de nuevo.')),
        duration: const Duration(seconds: 8),
      ));
  }
}

/// Cambia el nombre visible (Auth) y el guardado en users/{uid}.
Future<void> _editName(BuildContext context, User user) async {
  final controller = TextEditingController(text: user.displayName ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tu nombre'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nombre'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  controller.dispose();
  final clean = name?.trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
  if (clean.isEmpty) return;
  await user.updateDisplayName(clean);
  await Repository.instance.updateMyName(user.uid, clean);
  await user.reload();
}
