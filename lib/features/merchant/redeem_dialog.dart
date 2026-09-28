import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../data/repository.dart';

/// El comercio tipea el código de 6 caracteres que muestra el cliente
/// (el mismo que va dentro del QR). Escanear con cámara: ver ROADMAP.
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
        SnackBar(content: Text('✅ Entregado: $bagTitle')),
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
            const Text('Ingresa el código que aparece bajo el QR del cliente.'),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              autofocus: true,
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
