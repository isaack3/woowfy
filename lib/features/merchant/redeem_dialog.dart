import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/web_qr.dart';
import '../../data/repository.dart';
import 'qr_scanner_page.dart';

/// El comercio tipea el código de 6 caracteres que muestra el cliente
/// (el mismo que va dentro del QR) o lo escanea con la cámara.
class RedeemDialog extends StatefulWidget {
  const RedeemDialog({super.key});

  @override
  State<RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<RedeemDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    // En la web usamos el escáner HTML propio (web/qr_scanner.js); mobile_scanner queda para la app nativa.
    final code = WebQr.available
        ? await WebQr.scan()
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(fullscreenDialog: true, builder: (_) => const QrScannerPage()),
          );
    if (code == null || !mounted) return;
    _code.text = code;
    await _redeem();
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bagTitle = await Repository.instance.redeemOrder(_code.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Entregado: $bagTitle')),
      );
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Validar retiro'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear QR'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 16),
            const Text('O escribe el código que aparece bajo el QR:'),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 24, letterSpacing: 6),
              decoration: InputDecoration(labelText: 'Código', errorText: _error),
              onSubmitted: (_) => _redeem(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _redeem, child: const Text('Entregar')),
      ],
    );
  }
}
