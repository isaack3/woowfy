import 'package:flutter/widgets.dart';

import 'analytics_stub.dart' if (dart.library.js_interop) 'analytics_web.dart' as impl;
import 'backend.dart';

/// Analítica anónima: suma contadores por día en el servidor (sin cookies ni datos personales).
/// Ver functions/src/analytics.ts para la lista de eventos.
class Analytics {
  static void track(String event) {
    if (useEmulators) return; // en desarrollo no se cuenta nada
    impl.sendEvent(event);
  }

  /// Registra [event] una sola vez por sesión del navegador (p. ej. visitas).
  static void trackOncePerSession(String event) {
    if (useEmulators) return;
    if (impl.firstInSession('woowfy.$event')) impl.sendEvent(event);
  }
}

/// Registra [event] una sola vez cuando la pantalla se abre (no en cada reconstrucción).
class TrackView extends StatefulWidget {
  const TrackView({super.key, required this.event, required this.child});

  final String event;
  final Widget child;

  @override
  State<TrackView> createState() => _TrackViewState();
}

class _TrackViewState extends State<TrackView> {
  @override
  void initState() {
    super.initState();
    Analytics.track(widget.event);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
