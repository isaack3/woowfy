import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/push.dart';
import '../../core/pwa.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Estimación de emisiones evitadas por bolsa rescatada (kg CO₂e). Referencial.
const _co2PerBag = 2.5;

/// Tu impacto: bolsas rescatadas, dinero ahorrado y CO₂ evitado.
class ImpactCard extends StatelessWidget {
  const ImpactCard({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<BagOrder>>(
      stream: Repository.instance.watchMyOrders(uid),
      builder: (context, snap) {
        final rescued = (snap.data ?? const <BagOrder>[])
            .where((o) => o.status == OrderStatus.paid || o.status == OrderStatus.pickedUp)
            .toList();
        final saved = rescued.fold<int>(0, (s, o) => s + ((o.originalPrice ?? o.amount) - o.amount));
        final co2 = rescued.length * _co2PerBag;
        Widget stat(String value, String label) => Expanded(
              child: Column(children: [
                Text(value, style: t.headlineSmall?.copyWith(color: WoowfyColors.cream)),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: WoowfyColors.lime)),
              ]),
            );
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: WoowfyColors.green, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tu impacto', style: t.titleMedium?.copyWith(color: WoowfyColors.cream)),
              const SizedBox(height: 14),
              Row(children: [
                stat('${rescued.length}', rescued.length == 1 ? 'bolsa rescatada' : 'bolsas rescatadas'),
                stat(formatClp(saved), 'ahorrados'),
                stat('${co2.toStringAsFixed(co2 % 1 == 0 ? 0 : 1).replaceAll('.', ',')} kg', 'CO₂ evitado*'),
              ]),
              const SizedBox(height: 10),
              Text(
                rescued.isEmpty
                    ? 'Rescata tu primera bolsa y empieza a sumar.'
                    : '*Estimación referencial por comida que no terminó en la basura.',
                style: t.bodySmall?.copyWith(color: WoowfyColors.cream.withValues(alpha: .8)),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Notificaciones push e instalación de la app en la pantalla de inicio.
class AppSettingsCard extends StatefulWidget {
  const AppSettingsCard({super.key, required this.uid});

  final String? uid;

  @override
  State<AppSettingsCard> createState() => _AppSettingsCardState();
}

class _AppSettingsCardState extends State<AppSettingsCard> {
  bool _busy = false;

  Future<void> _enablePush() async {
    setState(() => _busy = true);
    final error = await Push.enable(widget.uid!);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Listo. Te avisaremos cuando tus locales favoritos publiquen y antes de cada retiro.'),
    ));
  }

  Future<void> _install() async {
    if (Pwa.canPrompt) {
      await Pwa.prompt();
      if (mounted) setState(() {});
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Instalar Woowfy'),
        content: Text(Pwa.isIos
            ? 'En Safari toca el botón Compartir (el cuadrado con la flecha) y elige "Agregar a inicio".'
            : 'Abre el menú de tu navegador (⋮) y elige "Instalar aplicación" o "Agregar a la pantalla principal".'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(children: [
        if (!Pwa.isInstalled)
          ListTile(
            leading: const Icon(Icons.install_mobile_outlined, color: WoowfyColors.green),
            title: const Text('Instalar la app'),
            subtitle: const Text('Ábrela desde tu pantalla de inicio, sin tiendas de apps'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _install,
          ),
        if (!Pwa.isInstalled && widget.uid != null) const Divider(height: 1),
        if (widget.uid != null)
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined, color: WoowfyColors.green),
            title: const Text('Notificaciones'),
            subtitle: Text(Push.configured
                ? 'Cuando tus favoritos publiquen y antes de cada retiro'
                : 'Muy pronto: avisos de favoritos y recordatorios de retiro'),
            trailing: Push.configured
                ? TextButton(onPressed: _busy ? null : _enablePush, child: Text(_busy ? 'Activando…' : 'Activar'))
                : null,
          ),
      ]),
    );
  }
}
