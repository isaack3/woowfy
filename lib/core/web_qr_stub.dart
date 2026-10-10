/// Resultado de validar un código en el modo mostrador.
/// [retry]: el problema fue de conexión, así que el mismo QR se puede volver a leer de inmediato.
/// [early]: llegó antes del horario; el local puede entregar igual (se vuelve a validar con force).
typedef CounterResult = ({bool ok, String title, String detail, bool retry, bool early});

/// Fuera de la web se usa QrScannerPage (mobile_scanner nativo).
class WebQr {
  static bool get available => false;

  static Future<String?> scan() async => null;

  static Future<bool> counter({int? pending, required Future<CounterResult> Function(String code, bool force) validate}) async =>
      false;
}
