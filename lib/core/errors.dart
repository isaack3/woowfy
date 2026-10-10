import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Códigos de Cloud Functions cuyo mensaje lo escribimos nosotros (en español) y se puede mostrar tal cual.
const _ownMessageCodes = {
  'failed-precondition',
  'not-found',
  'permission-denied',
  'resource-exhausted',
  'invalid-argument',
  'already-exists',
  'unauthenticated',
  'out-of-range',
};

/// Convierte cualquier error en un texto para personas. El detalle técnico va solo a la consola.
String friendlyError(Object error, {String fallback = 'Algo salió mal. Intenta de nuevo.'}) {
  debugPrint('Error: $error');
  if (error is FirebaseFunctionsException) {
    final message = error.message;
    if (_ownMessageCodes.contains(error.code) && message != null && message.isNotEmpty) return message;
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') return _offline;
    return fallback;
  }
  if (error is FirebaseException) {
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') return _offline;
    if (error.code == 'permission-denied') return 'No tienes permiso para ver esto.';
    return fallback;
  }
  return fallback;
}

const _offline = 'Revisa tu conexión e intenta de nuevo.';

/// Estado de error de una pantalla o sección: qué pasó, qué hacer y un botón "Reintentar".
///
/// Si no se pasa [onRetry], reintenta el [Reloadable] más cercano (si hay uno).
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.title, required this.error, this.onRetry});

  /// Qué no se pudo hacer, p. ej. "No pudimos cargar las bolsas".
  final String title;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry ?? Reloadable.retryOf(context);
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 44, color: WoowfyColors.green.withValues(alpha: .6)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              error == null ? _offline : friendlyError(error!, fallback: _offline),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: WoowfyColors.muted),
            ),
            if (retry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vuelve a construir [builder] desde cero (con streams nuevos) cuando un [ErrorRetry] de adentro pide reintentar.
class Reloadable extends StatefulWidget {
  const Reloadable({super.key, required this.builder});

  final WidgetBuilder builder;

  /// El reintento del [Reloadable] más cercano, o null si no hay.
  static VoidCallback? retryOf(BuildContext context) => context.findAncestorStateOfType<_ReloadableState>()?.reload;

  @override
  State<Reloadable> createState() => _ReloadableState();
}

class _ReloadableState extends State<Reloadable> {
  int _attempt = 0;

  void reload() => setState(() => _attempt++);

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: ValueKey(_attempt), child: Builder(builder: widget.builder));
}
