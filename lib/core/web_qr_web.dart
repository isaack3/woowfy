import 'dart:js_interop';

@JS('woowfyQr.scan')
external JSPromise<JSString?> _scan();

/// Escáner de QR de web/qr_scanner.js: una capa HTML sobre la app que funciona en Safari de iPhone.
class WebQr {
  static bool get available => true;

  /// Devuelve el código de 6 caracteres, o null si se cerró o se eligió escribirlo a mano.
  static Future<String?> scan() async {
    try {
      return (await _scan().toDart)?.toDart;
    } catch (_) {
      return null; // script no cargado (p. ej. caché vieja): queda la opción de escribir el código
    }
  }
}
