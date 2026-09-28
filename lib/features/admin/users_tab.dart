import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

final _date = DateFormat('d MMM y', 'es_CL');

/// Admin → Usuarios: buscar cuentas y dar o quitar el rol de administrador.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  final _users = Repository.instance.watchUsers();
  String _query = '';
  bool _onlyAdmins = false;

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<AppUser>>(
      stream: _users,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final q = _query.trim().toLowerCase();
        final shown = all.where((u) {
          if (_onlyAdmins && !u.isAdmin) return false;
          return q.isEmpty || u.email.toLowerCase().contains(q) || u.name.toLowerCase().contains(q);
        }).toList();
        final admins = all.where((u) => u.isAdmin).length;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre o correo'),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  FilterChip(
                    label: Text('Solo admins ($admins)'),
                    selected: _onlyAdmins,
                    showCheckmark: false,
                    selectedColor: WoowfyColors.lime,
                    onSelected: (v) => setState(() => _onlyAdmins = v),
                  ),
                  Text('${all.length} usuarios', style: const TextStyle(color: WoowfyColors.muted)),
                ]),
                const SizedBox(height: 12),
                if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Sin resultados.'))),
                for (final u in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: u.isAdmin ? WoowfyColors.green : WoowfyColors.limeSoft,
                          foregroundColor: u.isAdmin ? WoowfyColors.lime : WoowfyColors.green,
                          child: Text((u.name.isNotEmpty ? u.name : u.email).substring(0, 1).toUpperCase()),
                        ),
                        title: Text(u.name.isEmpty ? u.email : u.name),
                        subtitle: Text([
                          if (u.name.isNotEmpty) u.email,
                          if (u.createdAt != null) 'desde ${_date.format(u.createdAt!)}',
                        ].join(' · ')),
                        trailing: u.id == myUid
                            ? const Chip(label: Text('Tú · admin'))
                            : u.isAdmin
                                ? OutlinedButton(onPressed: () => _setRole(context, u, 'customer'), child: const Text('Quitar admin'))
                                : TextButton(onPressed: () => _setRole(context, u, 'admin'), child: const Text('Hacer admin')),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _setRole(BuildContext context, AppUser u, String role) async {
    final makeAdmin = role == 'admin';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(makeAdmin ? 'Dar acceso de admin' : 'Quitar acceso de admin'),
        content: Text(makeAdmin
            ? '${u.email} podrá aprobar comercios, ver ventas, inscritos y cambiar la configuración.'
            : '${u.email} dejará de ver el panel admin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(makeAdmin ? 'Hacer admin' : 'Quitar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repository.instance.setUserRole(u.id, role);
      messenger.showSnackBar(SnackBar(content: Text(makeAdmin ? '${u.email} ahora es admin' : '${u.email} ya no es admin')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo cambiar el rol: $e')));
    }
  }
}
