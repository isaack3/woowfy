import 'dart:js_interop';

@JS('navigator.sendBeacon')
external bool _sendBeacon(String url, String data);

@JS('sessionStorage.getItem')
external String? _sessionGet(String key);

@JS('sessionStorage.setItem')
external void _sessionSet(String key, String value);

/// Envía el evento a /api/track (rewrite de Hosting → función trackEvent) sin bloquear la app.
void sendEvent(String event) {
  try {
    _sendBeacon('/api/track', '{"e":"$event"}');
  } catch (_) {
    // Navegador sin sendBeacon o bloqueado por una extensión: no es importante.
  }
}

/// true solo la primera vez en esta sesión del navegador (pestaña), para contar visitas y no recargas.
bool firstInSession(String key) {
  try {
    if (_sessionGet(key) != null) return false;
    _sessionSet(key, '1');
    return true;
  } catch (_) {
    return false; // sin almacenamiento: mejor no contar que contar de más
  }
}
