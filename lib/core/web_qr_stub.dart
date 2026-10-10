/// Resultado de validar un código en el modo mostrador.
typedef CounterResult = ({bool ok, String title, String detail});

/// Fuera de la web se usa QrScannerPage (mobile_scanner nativo).
class WebQr {
  static bool get available => false;

  static Future<String?> scan() async => null;

  static Future<bool> counter({int? pending, required Future<CounterResult> Function(String code) validate}) async =>
      false;
}
