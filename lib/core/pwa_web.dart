import 'dart:js_interop';

@JS('woowfyPwa.canPrompt')
external bool _canPrompt();

@JS('woowfyPwa.isInstalled')
external bool _isInstalled();

@JS('woowfyPwa.isIos')
external bool _isIos();

@JS('woowfyPwa.prompt')
external JSPromise<JSBoolean> _prompt();

/// Puente con el script de web/index.html que captura el evento `beforeinstallprompt`.
class Pwa {
  static bool _safe(bool Function() f) {
    try {
      return f();
    } catch (_) {
      return false;
    }
  }

  /// Chrome/Edge/Android ofrecen el diálogo nativo de instalación.
  static bool get canPrompt => _safe(() => _canPrompt());

  /// Ya se abrió como app instalada.
  static bool get isInstalled => _safe(() => _isInstalled());

  /// En iPhone/iPad se instala desde Compartir → "Agregar a inicio".
  static bool get isIos => _safe(() => _isIos());

  static Future<bool> prompt() async {
    try {
      return (await _prompt().toDart).toDart;
    } catch (_) {
      return false;
    }
  }
}
