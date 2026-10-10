import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/backend.dart';
import '../../core/legal.dart';
import '../../core/theme.dart';
import '../../data/chile.dart';

/// Misma lista de espera que la landing (función joinWaitlist), sin salir de la app.
Uri get _endpoint => useEmulators
    ? Uri.parse('http://127.0.0.1:5001/woowfy-app/southamerica-west1/joinWaitlist')
    : Uri.parse('https://woowfy.com/api/waitlist');

/// "Avísame cuando haya bolsas": nombre, correo, región y comuna. Con sesión, nombre y correo vienen escritos.
class WaitlistForm extends StatefulWidget {
  const WaitlistForm({super.key, this.region});

  /// Región elegida en la Home (se preselecciona).
  final String? region;

  @override
  State<WaitlistForm> createState() => _WaitlistFormState();
}

class _WaitlistFormState extends State<WaitlistForm> {
  final _form = GlobalKey<FormState>();
  final _user = FirebaseAuth.instance.currentUser;
  late final _name = TextEditingController(text: _user?.displayName ?? '');
  late final _email = TextEditingController(text: _user?.email ?? '');
  final _comuna = TextEditingController();
  late String? _region = widget.region;
  bool _consent = false;
  bool _sending = false;
  String? _error;

  /// null mientras no se envía; true si ya estaba inscrito.
  bool? _doneAlready;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _comuna.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    if (!_consent) {
      setState(() => _error = 'Marca la casilla para que podamos escribirte.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            _endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': _name.text.trim(),
              'email': _email.text.trim(),
              'type': 'cliente',
              'region': _region,
              'comuna': _comuna.text.trim(),
              'consent': true,
            }),
          )
          .timeout(const Duration(seconds: 20));
      // Un error del servidor puede no venir en JSON: no confundirlo con falta de conexión.
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (res.statusCode != 200 || body == null) {
        setState(() => _error = body?['error'] as String? ?? 'No pudimos inscribirte. Intenta de nuevo.');
        return;
      }
      setState(() => _doneAlready = body!['already'] == true);
    } catch (_) {
      setState(() => _error = 'Sin conexión. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_doneAlready != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.mark_email_read_outlined, color: WoowfyColors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _doneAlready!
                    ? '¡Ya estabas en la lista! Te escribiremos cuando haya bolsas en tu región.'
                    : '¡Listo! Te escribiremos una sola vez cuando haya bolsas en $_region.',
                style: t.bodyLarge,
              ),
            ),
          ]),
        ),
      );
    }
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Te avisamos cuando haya bolsas', style: t.titleMedium),
          const SizedBox(height: 8),
          TextFormField(
            controller: _name,
            autofillHints: const [AutofillHints.givenName],
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre'),
            validator: required,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo'),
            validator: (v) => (v == null || !v.contains('@')) ? 'Revisa tu correo' : null,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _region,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Región'),
            items: [for (final r in chileRegions) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => setState(() => _region = v),
            validator: (v) => v == null ? 'Elige tu región' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _comuna,
            autofillHints: const [AutofillHints.addressCity],
            decoration: const InputDecoration(labelText: 'Comuna'),
            validator: required,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (v) => setState(() {
              _consent = v ?? false;
              _error = null;
            }),
            title: Text('Acepto que Woowfy me escriba para avisarme (una sola vez).', style: t.bodyMedium),
            subtitle: const LegalNotice(prefix: 'Puedo pedir que borren mis datos cuando quiera. Más en'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Enviando…' : 'Avísame'),
          ),
        ]),
      ),
    );
  }
}
