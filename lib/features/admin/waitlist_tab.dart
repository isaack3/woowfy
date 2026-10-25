import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'email_settings_tab.dart' show EmailTemplatesDialog;

final _date = DateFormat('d MMM y, HH:mm', 'es_CL');

/// Personas y locales inscritos en "Avísame cuando lancen" (landing).
class WaitlistTab extends StatefulWidget {
  const WaitlistTab({super.key});

  @override
  State<WaitlistTab> createState() => _WaitlistTabState();
}

class _WaitlistTabState extends State<WaitlistTab> {
  bool? _merchants; // null = todos
  String _query = '';

  bool _matches(WaitlistEntry e) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [e.name, e.email, e.businessName, e.comuna, e.region]
        .whereType<String>()
        .any((v) => v.toLowerCase().contains(q));
  }

  /// Borra sus datos de la lista de espera (lo que promete la landing al inscribirse).
  Future<void> _delete(BuildContext context, WaitlistEntry e) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar sus datos'),
        content: Text('Se eliminará a ${e.name.isEmpty ? e.email : '${e.name} (${e.email})'} de la lista de espera. '
            'Esto no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repository.instance.deleteWaitlistEntry(e.id);
      messenger.showSnackBar(SnackBar(content: Text('Datos de ${e.email} borrados.')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(err, fallback: 'No se pudo borrar. Intenta de nuevo.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Reloadable(builder: (context) => StreamBuilder<List<WaitlistEntry>>(
      stream: Repository.instance.watchWaitlist(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar los interesados', error: snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final merchants = all.where((e) => e.isMerchant).length;
        final shown = (_merchants == null ? all : all.where((e) => e.isMerchant == _merchants)).where(_matches).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _LaunchCard(),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre, correo o comuna',
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool?>(
                  segments: [
                    ButtonSegment(value: null, label: Text('Todos (${all.length})')),
                    ButtonSegment(value: false, label: Text('Clientes (${all.length - merchants})')),
                    ButtonSegment(value: true, label: Text('Locales ($merchants)')),
                  ],
                  selected: {_merchants},
                  onSelectionChanged: (v) => setState(() => _merchants = v.first),
                ),
                TextButton.icon(
                  onPressed: shown.isEmpty ? null : () => _copyEmails(context, shown),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar correos'),
                ),
                TextButton.icon(
                  onPressed: shown.isEmpty ? null : () => _copyCsv(context, shown),
                  icon: const Icon(Icons.table_view_outlined, size: 18),
                  label: const Text('Copiar CSV'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(all.isEmpty ? 'Aún no hay inscritos.' : 'Nadie coincide con la búsqueda.')),
              ),
            for (final e in shown)
              Card(
                child: ListTile(
                  leading: Icon(e.isMerchant ? Icons.storefront_outlined : Icons.person_outline),
                  title: Text(e.name.isEmpty ? e.email : e.name),
                  subtitle: Text([
                    if (e.name.isNotEmpty) e.email,
                    if (e.businessName != null) e.businessName!,
                    if (e.comuna != null) e.comuna!,
                    if (e.region != null) e.region!,
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (e.createdAt != null) Text(_date.format(e.createdAt!), style: Theme.of(context).textTheme.bodySmall),
                        _EmailBadge(status: e.emailStatus),
                      ],
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      onSelected: (_) => _delete(context, e),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Borrar sus datos')),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
          ],
        );
      },
    ));
  }

  Future<void> _copyCsv(BuildContext context, List<WaitlistEntry> entries) async {
    String cell(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final rows = [
      'nombre,correo,tipo,local,comuna,region',
      for (final e in entries)
        [e.name, e.email, e.isMerchant ? 'comercio' : 'cliente', e.businessName, e.comuna, e.region].map(cell).join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV con ${entries.length} filas copiado (pégalo en Excel o Google Sheets)')),
      );
    }
  }

  Future<void> _copyEmails(BuildContext context, List<WaitlistEntry> entries) async {
    await Clipboard.setData(ClipboardData(text: entries.map((e) => e.email).join(', ')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${entries.length} correos copiados')));
    }
  }
}

/// Estado del correo de bienvenida de cada inscrito.
class _EmailBadge extends StatelessWidget {
  const _EmailBadge({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      'sent' => (Icons.mark_email_read_outlined, 'Bienvenida enviada', WoowfyColors.green),
      'error' => (Icons.error_outline, 'Error al enviar', const Color(0xFFB83A22)),
      'skipped' => (Icons.do_not_disturb_on_outlined, 'Correo apagado', WoowfyColors.muted),
      _ => (Icons.schedule, 'Correo pendiente', WoowfyColors.muted),
    };
    return Tooltip(
      message: label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

/// Cambia el modo de woowfy.com, con confirmación.
Future<void> toggleSiteLaunch(BuildContext context, bool launched) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(launched ? 'Lanzar Woowfy' : 'Volver a "en construcción"'),
      content: Text(launched
          ? 'woowfy.com dejará de decir "en construcción" y llevará a las personas a la app para comprar y a los '
              'locales a pedir su alta. Hazlo cuando tengas locales activos y pagos reales.'
          : 'woowfy.com volverá a mostrar "en construcción" y la lista de espera.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(launched ? 'Lanzar' : 'Volver')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  // El aviso de arriba desaparece al lanzar: el diálogo siguiente se abre desde el Navigator, que sigue montado.
  final navigator = Navigator.of(context);
  try {
    await Repository.instance.setSiteLaunched(launched);
    messenger.showSnackBar(SnackBar(
      content: Text(launched ? 'woowfy.com ya está lanzada.' : 'woowfy.com volvió a "en construcción".'),
    ));
    if (launched && navigator.mounted) await showLaunchEmailDialog(navigator.context);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(friendlyError(e, fallback: 'No se pudo cambiar el modo de woowfy.com. Intenta de nuevo.')),
    ));
  }
}

/// Ofrece mandar el aviso de lanzamiento a quienes esperan en la lista (se abre al lanzar y desde Interesados).
Future<void> showLaunchEmailDialog(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _LaunchEmailDialog());

class _LaunchEmailDialog extends StatefulWidget {
  const _LaunchEmailDialog();

  @override
  State<_LaunchEmailDialog> createState() => _LaunchEmailDialogState();
}

class _LaunchEmailDialogState extends State<_LaunchEmailDialog> {
  bool _sending = false;
  String? _result;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final r = await Repository.instance.sendLaunchEmails();
      final parts = ['Enviados: ${r.sent}.'];
      if (r.failed > 0) parts.add('Con error: ${r.failed} (puedes reintentar más tarde).');
      if (r.remaining > 0) {
        parts.add(r.stoppedBy == 'limit'
            ? 'Faltan ${r.remaining}: se alcanzó el límite diario de Resend. Vuelve a enviar mañana y seguirá con ellos.'
            : 'Faltan ${r.remaining}: vuelve a presionar "Enviar" para seguir.');
      }
      setState(() => _result = parts.join(' '));
    } catch (e) {
      setState(() => _result = friendlyError(e, fallback: 'No se pudo enviar el aviso. Intenta de nuevo.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final repo = Repository.instance;
    return PopScope(
      canPop: !_sending,
      child: StreamBuilder<List<WaitlistEntry>>(
        stream: repo.watchWaitlist(),
        builder: (context, list) => StreamBuilder<EmailSettings>(
          stream: repo.watchEmailSettings(),
          builder: (context, settings) {
            final pending = (list.data ?? const <WaitlistEntry>[]).where((e) => e.awaitsLaunchEmail).length;
            final enabled = settings.data?.enabled ?? false;
            final loading = !list.hasData || !settings.hasData;
            return AlertDialog(
              title: const Text('Avisar a la lista de espera'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(loading
                      ? 'Revisando la lista…'
                      : pending == 0
                          ? 'Nadie espera el aviso: todos los inscritos ya lo recibieron.'
                          : '$pending ${pending == 1 ? 'persona espera' : 'personas esperan'} el aviso de lanzamiento. '
                              'Les llegará un correo invitándolas a entrar a la app (a los locales, a sumar su local). '
                              'Se envía una sola vez a cada uno.'),
                  if (!loading && !enabled) ...[
                    const SizedBox(height: 12),
                    Text('Los correos están apagados: actívalos en Admin → Correo para poder enviar.',
                        style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ],
                  if (pending > 100) ...[
                    const SizedBox(height: 12),
                    Text('El plan gratis de Resend envía hasta 100 correos al día. Si se alcanza el límite, vuelve a '
                        'enviar mañana y seguirá con los que falten.', style: t.bodySmall),
                  ],
                  if (_sending) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text('Enviando… puede tardar unos minutos. No cierres esta ventana.', style: t.bodySmall),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    Text(_result!, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const EmailTemplatesDialog(initialKind: 'launch'),
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Ver el correo'),
                  ),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: _sending ? null : () => Navigator.pop(context),
                  child: Text(_result == null ? 'Ahora no' : 'Cerrar'),
                ),
                FilledButton.icon(
                  onPressed: loading || !enabled || pending == 0 || _sending ? null : _send,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(pending == 0 ? 'Enviar' : 'Enviar a $pending'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Ya lanzada: cuántos recibieron el aviso de lanzamiento y botón para enviarlo a los que faltan.
class _LaunchEmailStatus extends StatelessWidget {
  const _LaunchEmailStatus();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<List<WaitlistEntry>>(
      stream: Repository.instance.watchWaitlist(),
      builder: (context, snap) {
        final all = snap.data ?? const <WaitlistEntry>[];
        final sent = all.where((e) => e.launchEmailStatus == 'sent').length;
        final pending = all.where((e) => e.awaitsLaunchEmail).length;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.mark_email_read_outlined, size: 18, color: WoowfyColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Aviso de lanzamiento: $sent ${sent == 1 ? 'enviado' : 'enviados'}'
                '${pending > 0 ? ' · $pending ${pending == 1 ? 'pendiente' : 'pendientes'}' : ''}',
                style: t.bodySmall,
              ),
            ),
            if (pending > 0)
              TextButton(onPressed: () => showLaunchEmailDialog(context), child: const Text('Enviar')),
          ]),
        );
      },
    );
  }
}

/// Mientras woowfy.com siga "en construcción", un aviso arriba de todas las pestañas del admin con el botón para
/// lanzar (antes estaba escondido en Interesados). Ya lanzada, desaparece; el interruptor sigue en Interesados.
class LaunchBanner extends StatelessWidget {
  const LaunchBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<bool>(
      stream: Repository.instance.watchSiteLaunched(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data == true) return const SizedBox.shrink();
        return Material(
          color: WoowfyColors.orangeSoft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(children: [
              const Icon(Icons.construction_outlined, color: WoowfyColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('woowfy.com está "en construcción"', style: t.titleSmall),
                  FutureBuilder<int>(
                    future: Repository.instance.waitlistCount(),
                    builder: (context, n) => Text(
                      n.hasData ? '${n.data} ${n.data == 1 ? 'interesado espera' : 'interesados esperan'} el lanzamiento' : ' ',
                      style: t.bodySmall,
                    ),
                  ),
                ]),
              ),
              FilledButton.icon(
                onPressed: () => toggleSiteLaunch(context, true),
                icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                label: const Text('Lanzar'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// Interruptor del modo de la landing (woowfy.com): "en construcción" con lista de espera, o lanzada con acceso a la app.
class _LaunchCard extends StatelessWidget {
  const _LaunchCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<bool>(
      stream: Repository.instance.watchSiteLaunched(),
      builder: (context, snap) {
        final launched = snap.data ?? false;
        return Card(
          color: launched ? WoowfyColors.limeSoft : WoowfyColors.orangeSoft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(children: [
              Row(children: [
                Icon(launched ? Icons.rocket_launch_outlined : Icons.construction_outlined, color: WoowfyColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(launched ? 'woowfy.com está lanzada' : 'woowfy.com está "en construcción"', style: t.titleSmall),
                    Text(
                      launched
                          ? 'Los botones llevan a la app; la lista de espera queda para comunas sin locales.'
                          : 'Los botones invitan a inscribirse en esta lista de espera.',
                      style: t.bodySmall,
                    ),
                  ]),
                ),
                Switch(value: launched, onChanged: snap.hasData ? (v) => toggleSiteLaunch(context, v) : null),
              ]),
              if (launched) const _LaunchEmailStatus(),
            ]),
          ),
        );
      },
    );
  }
}
