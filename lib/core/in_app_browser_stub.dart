/// Fuera de la web no hay navegador interno de otra app.
class InAppBrowser {
  /// Nombre de la app ("Instagram"), o null si es un navegador normal.
  static String? get appName => null;
  static bool get isAndroid => false;
}
