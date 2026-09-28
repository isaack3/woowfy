import 'dart:async';

import 'package:flutter/foundation.dart';

/// Notifica al router cuando cambia la sesión para re-evaluar redirecciones.
class AuthRefresh extends ChangeNotifier {
  AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
