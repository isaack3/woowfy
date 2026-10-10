import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('woowfyQr.scan')
external JSPromise<JSString?> _scan();

@JS('woowfyQr.counter')
external JSPromise<JSAny?> _counter(JSObject options);

/// Resultado de validar un código en el modo mostrador.
typedef CounterResult = ({bool ok, String title, String detail});

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

  /// Modo mostrador: cámara abierta y un cliente tras otro hasta que el comercio sale. [validate] llama al servidor.
  /// Devuelve false si el escáner no está disponible (p. ej. caché vieja sin el script nuevo).
  static Future<bool> counter({int? pending, required Future<CounterResult> Function(String code) validate}) async {
    final options = JSObject();
    if (pending != null) options.setProperty('pending'.toJS, pending.toJS);
    options.setProperty(
      'validate'.toJS,
      ((JSString code) => validate(code.toDart)
          .then((r) => {'ok': r.ok, 'title': r.title, 'detail': r.detail}.jsify())
          .toJS).toJS,
    );
    try {
      await _counter(options).toDart;
      return true;
    } catch (_) {
      return false;
    }
  }
}
