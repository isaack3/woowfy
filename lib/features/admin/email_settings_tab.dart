import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'email_preview.dart';

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// Único dominio verificado en Resend: la clave de envío solo acepta remitentes de aquí (igual que en email.ts).
const senderDomain = 'woowfy.com';

/// Admin → Correo: remitente de los correos automáticos (bienvenida a la lista de espera).
class EmailSettingsTab extends StatelessWidget {
  const EmailSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Reloadable(builder: (context) => StreamBuilder<EmailSettings>(
      stream: Repository.instance.watchEmailSettings(),
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar la configuración de correo', error: snap.error);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            // La key recrea el formulario si la configuración cambia desde otro lado.
            child: _Form(key: ValueKey(snap.data!.toMap().toString()), initial: snap.data!),
          ),
        );
      },
    ));
  }
}

class _Form extends StatefulWidget {
  const _Form({super.key, required this.initial});

  final EmailSettings initial;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late final _fromName = TextEditingController(text: widget.initial.fromName);
  late final _fromEmail = TextEditingController(text: widget.initial.fromEmail);
  late final _replyTo = TextEditingController(text: widget.initial.replyTo ?? '');
  late bool _enabled = widget.initial.enabled;
  late bool _orderEmails = widget.initial.orderEmails;
  bool _saving = false;
  bool _testing = false;

  @override
  void dispose() {
    _fromName.dispose();
    _fromEmail.dispose();
    _replyTo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Repository.instance.saveEmailSettings(EmailSettings(
        enabled: _enabled,
        orderEmails: _orderEmails,
        fromName: _fromName.text.trim(),
        fromEmail: _fromEmail.text.trim().toLowerCase(),
        replyTo: _replyTo.text.trim().isEmpty ? null : _replyTo.text.trim().toLowerCase(),
      ));
      messenger.showSnackBar(const SnackBar(content: Text('Configuración guardada')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e, fallback: 'No se pudo guardar. Intenta de nuevo.'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest(String kind) async {
    setState(() => _testing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final to = await Repository.instance.sendTestEmail(kind);
      messenger.showSnackBar(SnackBar(content: Text('Correo de prueba enviado a $to')));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Falló el envío: ${friendlyError(e)}')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String? email(String? v, {bool optional = false}) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return optional ? null : 'Campo obligatorio';
      return _emailRe.hasMatch(s) ? null : 'Correo no válido';
    }

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Correos automáticos', style: t.titleLarge),
          const SizedBox(height: 4),
          const Text('Bienvenida a la lista de espera, confirmación de compra con el código de retiro, aviso de reembolso '
              'y aviso de lanzamiento (se envía desde "Lanzar").'),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar correos automáticos'),
            subtitle: const Text('Enciéndelo cuando Resend esté configurado. Apagado, todo funciona igual pero sin correos.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.only(left: 16),
            title: const Text('Compra y reembolso'),
            subtitle: const Text('Al pagar: código de retiro y horario. Al reembolsar: monto y motivo.'),
            value: _orderEmails,
            onChanged: _enabled ? (v) => setState(() => _orderEmails = v) : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _fromName,
            decoration: const InputDecoration(labelText: 'Nombre del remitente', hintText: 'Woowfy'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Campo obligatorio' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _fromEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo del remitente',
              hintText: 'hola@woowfy.com',
              helperText: 'Debe terminar en @$senderDomain, el dominio verificado en Resend. Para recibir las '
                  'respuestas en otro correo (como @passva.com o tu Gmail), usa "Responder a".',
              helperMaxLines: 3,
              errorMaxLines: 3,
            ),
            validator: (v) {
              final err = email(v);
              if (err != null) return err;
              if (!v!.trim().toLowerCase().endsWith('@$senderDomain')) {
                return 'Usa una dirección @$senderDomain (por ejemplo hola@$senderDomain). La otra va en "Responder a".';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _replyTo,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Responder a (opcional)',
              hintText: 'hola@passva.com',
              helperText: 'Si alguien responde el correo, la respuesta llega aquí. Vacío = hola@passva.com.',
            ),
            validator: (v) => email(v, optional: true),
          ),
          const SizedBox(height: 24),
          // Los cambios solo valen al guardar: se avisa para no perderlos al cambiar de pestaña.
          ListenableBuilder(
            listenable: Listenable.merge([_fromName, _fromEmail, _replyTo]),
            builder: (context, _) {
              final dirty = _fromName.text != widget.initial.fromName ||
                  _fromEmail.text != widget.initial.fromEmail ||
                  _replyTo.text != (widget.initial.replyTo ?? '') ||
                  _enabled != widget.initial.enabled ||
                  _orderEmails != widget.initial.orderEmails;
              if (!dirty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.edit_note, size: 18, color: Color(0xFF7A3510)),
                  const SizedBox(width: 6),
                  Text('Tienes cambios sin guardar',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF7A3510), fontWeight: FontWeight.w700)),
                ]),
              );
            },
          ),
          Row(
            children: [
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                enabled: !_testing,
                tooltip: 'Enviar un correo de ejemplo a tu correo',
                onSelected: _sendTest,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'welcome', child: Text('Bienvenida a la lista de espera')),
                  PopupMenuItem(value: 'purchase', child: Text('Confirmación de compra')),
                  PopupMenuItem(value: 'refund', child: Text('Aviso de reembolso')),
                  PopupMenuItem(value: 'launch', child: Text('Aviso de lanzamiento (clientes)')),
                  PopupMenuItem(value: 'launch_store', child: Text('Aviso de lanzamiento (locales)')),
                ],
                child: IgnorePointer(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : () {},
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: Text(_testing ? 'Enviando…' : 'Enviar prueba a mi correo'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('La prueba usa la configuración guardada y datos de ejemplo.', style: t.bodySmall),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const EmailTemplatesDialog()),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Ver plantillas (sin enviar)'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muestra cómo se ve cada correo automático, con datos de ejemplo y sin enviar nada.
class EmailTemplatesDialog extends StatefulWidget {
  const EmailTemplatesDialog({super.key, this.initialKind = 'welcome'});

  /// welcome | purchase | refund | launch | launch_store
  final String initialKind;

  @override
  State<EmailTemplatesDialog> createState() => _EmailTemplatesDialogState();
}

class _EmailTemplatesDialogState extends State<EmailTemplatesDialog> {
  static const _kinds = {
    'welcome': 'Bienvenida',
    'purchase': 'Compra',
    'refund': 'Reembolso',
    'launch': 'Lanzamiento',
    'launch_store': 'Lanzamiento (locales)',
  };
  late String _kind = widget.initialKind;
  late Future<({String subject, String html})> _mail = Repository.instance.previewEmail(_kind);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 620,
        height: size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(children: [
                Expanded(child: Text('Plantillas de correo', style: t.titleLarge)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), tooltip: 'Cerrar'),
              ]),
            ),
            // Chips en vez de botones segmentados: con cinco plantillas así caben también en el celular.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final e in _kinds.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _kind == e.key,
                    onSelected: (_) => setState(() {
                      _kind = e.key;
                      _mail = Repository.instance.previewEmail(_kind);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<({String subject, String html})>(
                future: _mail,
                builder: (context, snap) {
                  if (snap.hasError) return ErrorRetry(title: 'No pudimos cargar la vista previa', error: snap.error, onRetry: () => setState(() => _mail = Repository.instance.previewEmail(_kind)));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(children: [
                        Text('Asunto: ', style: t.bodySmall),
                        Expanded(child: Text(snap.data!.subject, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                      ]),
                    ),
                    Expanded(child: EmailHtmlView(html: snap.data!.html)),
                  ]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('Datos de ejemplo. Los correos reales llevan los datos de cada pedido.', style: t.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
