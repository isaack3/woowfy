import 'dart:js_interop';

@JS('navigator.userAgent')
external String get _userAgent;

/// Detecta el navegador interno de una app por su user agent. WhatsApp no aparece: abre los enlaces en el
/// navegador del sistema (Chrome Custom Tabs / Safari), donde Google sí funciona.
class InAppBrowser {
  static final String _ua = _userAgent;

  static const _apps = {
    'Instagram': 'Instagram',
    'FBAN': 'Facebook',
    'FBAV': 'Facebook',
    'FB_IAB': 'Facebook',
    'musical_ly': 'TikTok',
    'BytedanceWebview': 'TikTok',
    'LinkedInApp': 'LinkedIn',
    'Snapchat': 'Snapchat',
    'Line/': 'LINE',
  };

  /// Nombre de la app ("Instagram"), o null si es un navegador normal.
  static String? get appName {
    for (final e in _apps.entries) {
      if (_ua.contains(e.key)) return e.value;
    }
    return null;
  }

  static bool get isAndroid => _ua.contains('Android');
}
