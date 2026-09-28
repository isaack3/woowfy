import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/legal.dart';
import '../../core/theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.redirectTo = '/'});

  final String redirectTo;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Crea `users/{uid}` la primera vez (registro con correo o primer ingreso con Google).
  Future<void> _ensureProfile(User user, {String? name}) async {
    final ref = FirebaseFirestore.instance.doc('users/${user.uid}');
    if ((await ref.get()).exists) return;
    await ref.set({
      'email': user.email,
      'name': (name ?? user.displayName ?? '').trim(),
      'role': 'customer',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) context.go(widget.redirectTo);
    } on FirebaseAuthException catch (e) {
      if (mounted && e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request') {
        setState(() => _error = _message(e.code));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = FirebaseAuth.instance;
    await _run(() async {
      if (_register) {
        final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        await cred.user!.updateDisplayName(_name.text.trim());
        await _ensureProfile(cred.user!, name: _name.text);
      } else {
        await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      }
    });
  }

  Future<void> _google() async {
    final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
    final auth = FirebaseAuth.instance;
    await _run(() async {
      final cred = kIsWeb ? await auth.signInWithPopup(provider) : await auth.signInWithProvider(provider);
      await _ensureProfile(cred.user!);
    });
  }

  Future<void> _forgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetPasswordDialog(initialEmail: _email.text.trim()),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Si el correo tiene una cuenta, te enviamos un enlace para crear una nueva contraseña. '
            'Revisa también la carpeta de spam.'),
        duration: Duration(seconds: 6),
      ));
    }
  }

  String _message(String code) => switch (code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' => 'Correo o contraseña incorrectos.',
        'email-already-in-use' => 'Ese correo ya tiene una cuenta. Ingresa o recupera tu contraseña.',
        'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
        'invalid-email' => 'El correo no es válido.',
        'too-many-requests' => 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.',
        'operation-not-allowed' => 'Este método de ingreso aún no está habilitado.',
        'popup-blocked' => 'Tu navegador bloqueó la ventana de Google. Permite ventanas emergentes e intenta de nuevo.',
        'account-exists-with-different-credential' =>
          'Ese correo ya está registrado con contraseña. Ingresa con tu correo y contraseña.',
        'network-request-failed' => 'Sin conexión. Revisa tu internet.',
        _ => 'No pudimos continuar ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  const Center(child: WoowfyLogo(size: 40)),
                  const SizedBox(height: 24),
                  Text(_register ? 'Crea tu cuenta' : 'Ingresa a Woowfy', style: t.headlineSmall),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _google,
                    icon: const _GoogleMark(),
                    label: const Text('Continuar con Google'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('o con tu correo', style: t.bodySmall)),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Cuéntanos tu nombre' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Ingresa un correo válido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (!_register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text(_loading ? 'Un momento…' : (_register ? 'Crear cuenta' : 'Ingresar')),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    const LegalNotice(prefix: 'Al crear tu cuenta aceptas'),
                  ],
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(_register ? 'Ya tengo cuenta' : 'Crear una cuenta nueva'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Ingresa un correo válido');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      // No revelamos si el correo existe: solo mostramos errores de formato o de red.
      if (e.code == 'user-not-found') {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() => _error = e.code == 'invalid-email' ? 'Ingresa un correo válido' : 'No pudimos enviar el correo (${e.code}).');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Recuperar contraseña'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Te enviaremos un enlace para crear una contraseña nueva.'),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'Correo', errorText: _error),
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Enviando…' : 'Enviar enlace')),
      ],
    );
  }
}

/// "G" de Google dibujada con sus colores oficiales (sin depender de imágenes externas).
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 18, height: 18, child: CustomPaint(painter: _GooglePainter()));
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s - stroke, s - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas.drawArc(rect, -40 * deg, -100 * deg, false, p(const Color(0xFFEA4335))); // rojo (arriba)
    canvas.drawArc(rect, -140 * deg, -90 * deg, false, p(const Color(0xFFFBBC05))); // amarillo (izquierda)
    canvas.drawArc(rect, 130 * deg, -90 * deg, false, p(const Color(0xFF34A853))); // verde (abajo)
    canvas.drawArc(rect, 40 * deg, -40 * deg, false, p(const Color(0xFF4285F4))); // azul (derecha)
    canvas.drawLine(Offset(s / 2, s / 2), Offset(s - stroke / 2, s / 2),
        Paint()..color = const Color(0xFF4285F4)..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
