import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/models.dart';
import '../../data/repository.dart';

final _date = DateFormat('d MMM y, HH:mm', 'es_CL');

/// Personas y locales inscritos en "Avísame cuando lancen" (landing).
class WaitlistTab extends StatefulWidget {
  const WaitlistTab({super.key});

  @override
  State<WaitlistTab> createState() => _WaitlistTabState();
}

class _WaitlistTabState extends State<WaitlistTab> {
  bool? _merchants; // null = todos

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WaitlistEntry>>(
      stream: Repository.instance.watchWaitlist(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final merchants = all.where((e) => e.isMerchant).length;
        final shown = _merchants == null ? all : all.where((e) => e.isMerchant == _merchants).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aún no hay inscritos.'))),
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
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (e.createdAt != null) Text(_date.format(e.createdAt!), style: Theme.of(context).textTheme.bodySmall),
                      _EmailBadge(status: e.emailStatus),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
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
      'sent' => (Icons.mark_email_read_outlined, 'Bienvenida enviada', Colors.green),
      'error' => (Icons.error_outline, 'Error al enviar', Theme.of(context).colorScheme.error),
      'skipped' => (Icons.do_not_disturb_on_outlined, 'Correo apagado', Colors.grey),
      _ => (Icons.schedule, 'Sin correo', Colors.grey),
    };
    return Tooltip(
      message: label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ]),
    );
  }
}
