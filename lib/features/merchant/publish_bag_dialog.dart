import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repository.dart';

class PublishBagDialog extends StatefulWidget {
  const PublishBagDialog({super.key, required this.store});

  final Store store;

  @override
  State<PublishBagDialog> createState() => _PublishBagDialogState();
}

class _PublishBagDialogState extends State<PublishBagDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Bolsa sorpresa');
  final _description = TextEditingController();
  final _originalPrice = TextEditingController();
  final _price = TextEditingController();
  final _quantity = TextEditingController(text: '3');
  TimeOfDay _start = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 20, minute: 30);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _description, _originalPrice, _price, _quantity]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime _today(TimeOfDay t) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, t.hour, t.minute);
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final original = int.parse(_originalPrice.text);
    final price = int.parse(_price.text);
    final start = _today(_start);
    final end = _today(_end);
    if (price >= original) {
      setState(() => _error = 'El precio debe ser menor al valor original.');
      return;
    }
    if (!end.isAfter(start) || end.isBefore(DateTime.now())) {
      setState(() => _error = 'Revisa el horario de retiro.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Repository.instance.publishBag(
        store: widget.store,
        title: _title.text.trim(),
        description: _description.text.trim(),
        originalPrice: original,
        price: price,
        quantity: int.parse(_quantity.text),
        pickupStart: start,
        pickupEnd: end,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'No se pudo publicar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? positiveInt(String? v) =>
        (int.tryParse(v ?? '') ?? 0) > 0 ? null : 'Ingresa un número mayor a 0';
    return AlertDialog(
      title: const Text('Publicar bolsa de hoy'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Nombre (ej. Bolsa panadería)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Qué podría incluir (opcional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _originalPrice,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Valor original \$'),
                        validator: positiveInt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Precio Woowfy \$'),
                        validator: positiveInt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cantidad de bolsas'),
                  validator: positiveInt,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Retiro hoy:'),
                    TextButton(onPressed: () => _pick(true), child: Text(_start.format(context))),
                    const Text('a'),
                    TextButton(onPressed: () => _pick(false), child: Text(_end.format(context))),
                  ],
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Publicar')),
      ],
    );
  }
}
