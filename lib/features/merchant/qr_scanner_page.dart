import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// Cámara para leer el QR del cliente. Devuelve el código de 6 caracteres (o null si se cancela).
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  /// En computador solo suele haber cámara frontal (webcam): pedir la trasera deja el visor en negro.
  static bool get _isDesktop =>
      kIsWeb && defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS;

  late final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    facing: _isDesktop ? CameraFacing.front : CameraFacing.back,
  );
  bool _done = false;
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _watchStart();
  }

  /// Si en 6 segundos la cámara no arrancó, mostramos ayuda en vez de dejar la pantalla negra.
  void _watchStart() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_controller.value.isRunning) setState(() => _slow = true);
    });
  }

  Future<void> _retry() async {
    setState(() => _slow = false);
    try {
      await _controller.stop();
      await _controller.start();
    } catch (_) {
      // El errorBuilder del escáner muestra el detalle.
    }
    _watchStart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = (b.rawValue ?? '').trim().toUpperCase();
      if (RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear QR'),
        actions: [
          IconButton(
            tooltip: 'Cambiar de cámara',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _Help(
              message: error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'No hay permiso para usar la cámara. Actívalo en el ícono de la barra de direcciones del navegador, '
                      'o escribe el código a mano.'
                  : 'No pudimos abrir la cámara (${error.errorCode.name}). Prueba cambiar de cámara o escribe el código a mano.',
            ),
          ),
          // Marco guía
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: WoowfyColors.lime, width: 4),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => (_slow && !state.isRunning && state.error == null)
                ? _Help(
                    message: 'La cámara no está enviando imagen. Revisa que el navegador tenga permiso, que tu equipo '
                        'tenga cámara, o usa el botón de arriba para cambiar de cámara.',
                    onRetry: _retry,
                  )
                : const SizedBox.shrink(),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: IgnorePointer(
              child: Text(
                'Apunta al QR del cliente',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ayuda sobre el visor cuando la cámara no funciona, con salida a escribir el código.
class _Help extends StatelessWidget {
  const _Help({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_outlined, size: 48, color: WoowfyColors.lime),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Escribir el código')),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: WoowfyColors.lime),
              child: const Text('Reintentar'),
            ),
        ],
      ),
    );
  }
}
