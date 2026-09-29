/// Fuera de la web se usa QrScannerPage (mobile_scanner nativo).
class WebQr {
  static bool get available => false;

  static Future<String?> scan() async => null;
}
