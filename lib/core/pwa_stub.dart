/// Fuera de la web no hay instalación PWA.
class Pwa {
  static bool get canPrompt => false;
  static bool get isInstalled => true;
  static bool get isIos => false;
  static Future<bool> prompt() async => false;
}
