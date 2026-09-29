import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
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
  Uint8List? _photo;
  bool _repeat = false;
  final Set<int> _days = {1, 2, 3, 4, 5, 6, 7};
  String _photoType = 'image/jpeg';

  Future<void> _pickPhoto() async {
    // Se reduce en el dispositivo antes de subir (fotos livianas y rápidas de cargar).
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      setState(() => _error = 'La foto pesa más de 5 MB. Elige otra.');
      return;
    }
    setState(() {
      _photo = bytes;
      _photoType = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      _error = null;
    });
  }

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
    // Una bolsa recurrente puede crearse aunque el horario de hoy ya pasó (parte mañana).
    if (!end.isAfter(start) || (!_repeat && end.isBefore(DateTime.now()))) {
      setState(() => _error = 'Revisa el horario de retiro.');
      return;
    }
    if (_repeat && _days.isEmpty) {
      setState(() => _error = 'Elige al menos un día.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imageUrl = _photo == null
          ? null
          : await Repository.instance.uploadBagImage(widget.store.ownerUid, _photo!, _photoType);
      if (_repeat) {
        String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        await Repository.instance.saveTemplate(
          storeId: widget.store.id,
          title: _title.text.trim(),
          description: _description.text.trim(),
          originalPrice: original,
          price: price,
          quantity: int.parse(_quantity.text),
          pickupStart: hhmm(_start),
          pickupEnd: hhmm(_end),
          days: (_days.toList()..sort()),
          imageUrl: imageUrl,
        );
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await Repository.instance.publishBag(
        imageUrl: imageUrl,
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
      title: Text(_repeat ? 'Bolsa recurrente' : 'Publicar bolsa de hoy'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhotoPicker(photo: _photo, onPick: _saving ? null : _pickPhoto, onRemove: () => setState(() => _photo = null)),
                const SizedBox(height: 12),
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
                        decoration: const InputDecoration(labelText: 'Normal', prefixText: '\$ '),
                        validator: positiveInt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Oferta', prefixText: '\$ '),
                        validator: positiveInt,
                      ),
                    ),
                  ],
                ),
                // Siempre a la vista: cuánto recibe el local y la comisión de Woowfy.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _price,
                  builder: (context, v, _) {
                    final price = int.tryParse(v.text.trim());
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        price == null || price <= 0
                            ? 'Woowfy cobra una comisión de $platformFeePercent sobre el precio de oferta.'
                            : 'Recibes ${formatClp(storeShareOf(price))} por bolsa (comisión Woowfy $platformFeePercent).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted),
                      ),
                    );
                  },
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
                    Text(_repeat ? 'Retiro:' : 'Retiro hoy:'),
                    TextButton(onPressed: () => _pick(true), child: Text(_start.format(context))),
                    const Text('a'),
                    TextButton(onPressed: () => _pick(false), child: Text(_end.format(context))),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Repetir'),
                  subtitle: const Text('Se publica sola los días que elijas'),
                  value: _repeat,
                  onChanged: (v) => setState(() => _repeat = v),
                ),
                if (_repeat)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(weekdayShort[d - 1]),
                          showCheckmark: false,
                          selected: _days.contains(d),
                          selectedColor: WoowfyColors.lime,
                          onSelected: (on) => setState(() => on ? _days.add(d) : _days.remove(d)),
                        ),
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
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Publicando…' : 'Publicar')),
      ],
    );
  }
}

/// Foto opcional de la bolsa: vista previa o botón para elegirla.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.photo, required this.onPick, required this.onRemove});

  final Uint8List? photo;
  final VoidCallback? onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: WoowfyColors.limeSoft,
          child: InkWell(
            onTap: onPick,
            child: photo == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: WoowfyColors.green),
                      SizedBox(height: 6),
                      Text('Agregar foto (opcional)', style: TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w700)),
                    ],
                  )
                : Stack(fit: StackFit.expand, children: [
                    Image.memory(photo!, fit: BoxFit.cover),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton.filled(
                        tooltip: 'Quitar foto',
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(backgroundColor: WoowfyColors.green, foregroundColor: WoowfyColors.cream),
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
