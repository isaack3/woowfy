import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Publicar (vacía, o con los datos de [from] para "igual que ayer"), editar una bolsa ([editBag]) o una recurrente
/// ([editTemplate]). Al publicar devuelve el id de la bolsa nueva.
class PublishBagDialog extends StatefulWidget {
  const PublishBagDialog({super.key, required this.store, this.from, this.editBag, this.editTemplate});

  final Store store;
  final Bag? from;
  final Bag? editBag;
  final BagTemplate? editTemplate;

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

  bool get _editing => widget.editBag != null || widget.editTemplate != null;

  /// Si la bolsa que se edita ya tiene compradores, su horario queda fijo (está en sus comprobantes).
  bool _timesLocked = false;

  static String _money(int v) => _ThousandsFormatter._group('$v');
  static TimeOfDay _hhmm(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 19, minute: int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  @override
  void initState() {
    super.initState();
    final t = widget.editTemplate;
    final b = widget.editBag ?? widget.from;
    if (t != null) {
      _repeat = true;
      _title.text = t.title;
      _description.text = t.description;
      _originalPrice.text = _money(t.originalPrice);
      _price.text = _money(t.price);
      _quantity.text = '${t.quantity}';
      _start = _hhmm(t.pickupStart);
      _end = _hhmm(t.pickupEnd);
      _days
        ..clear()
        ..addAll(t.days);
    } else if (b != null) {
      _title.text = b.title;
      _description.text = b.description;
      _originalPrice.text = _money(b.originalPrice);
      _price.text = _money(b.price);
      _start = TimeOfDay.fromDateTime(b.pickupStart);
      _end = TimeOfDay.fromDateTime(b.pickupEnd);
      // Al editar, la cantidad es "unidades a sumar"; al repetir, la misma de la vez anterior no se conoce: 3.
      _quantity.text = widget.editBag != null ? '0' : '3';
    }
    final edit = widget.editBag;
    if (edit != null) {
      Repository.instance.bagHasBuyers(widget.store.id, edit.id).then((v) {
        if (mounted) setState(() => _timesLocked = v);
      }).catchError((_) {
        if (mounted) setState(() => _timesLocked = true); // ante la duda, no se mueve el horario
      });
    }
  }

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
    final original = _amount(_originalPrice.text)!;
    final price = _amount(_price.text)!;
    final start = _today(_start);
    final end = _today(_end);
    if (price >= original) {
      setState(() => _error = 'La oferta debe ser menor al precio normal.');
      return;
    }
    if (!end.isAfter(start)) {
      setState(() => _error = 'El retiro termina antes de empezar. Revisa las horas.');
      return;
    }
    // Una bolsa recurrente puede crearse aunque el horario de hoy ya pasó (parte mañana).
    if (!_repeat && end.isBefore(DateTime.now())) {
      setState(() => _error = 'Ese horario de retiro ya pasó. Elige una hora más tarde.');
      return;
    }
    if (_repeat && _days.isEmpty) {
      setState(() => _error = 'Elige al menos un día.');
      return;
    }
    final editBag = widget.editBag;
    if (editBag != null) {
      await _run(() async {
        final imageUrl = _photo == null ? null : await Repository.instance.uploadBagImage(widget.store.ownerUid, _photo!, _photoType);
        await Repository.instance.updateBag(
          editBag.id,
          {
            'title': _title.text.trim(),
            'description': _description.text.trim(),
            'originalPrice': original,
            'price': price,
            if (!_timesLocked) 'pickupStart': Timestamp.fromDate(_onDay(editBag.pickupStart, _start)),
            if (!_timesLocked) 'pickupEnd': Timestamp.fromDate(_onDay(editBag.pickupEnd, _end)),
            'imageUrl': ?imageUrl,
          },
          addUnits: _amount(_quantity.text) ?? 0,
        );
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    final editTemplate = widget.editTemplate;
    if (editTemplate != null) {
      await _run(() async {
        String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final imageUrl = _photo == null ? null : await Repository.instance.uploadBagImage(widget.store.ownerUid, _photo!, _photoType);
        await Repository.instance.updateTemplate(editTemplate.id, {
          'title': _title.text.trim(),
          'description': _description.text.trim(),
          'originalPrice': original,
          'price': price,
          'quantity': int.parse(_quantity.text),
          'pickupStart': hhmm(_start),
          'pickupEnd': hhmm(_end),
          'days': (_days.toList()..sort()),
          'imageUrl': ?imageUrl,
        });
        if (mounted) Navigator.of(context).pop();
      });
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
      final id = await Repository.instance.publishBag(
        imageUrl: imageUrl ?? widget.from?.imageUrl,
        store: widget.store,
        title: _title.text.trim(),
        description: _description.text.trim(),
        originalPrice: original,
        price: price,
        quantity: int.parse(_quantity.text),
        pickupStart: start,
        pickupEnd: end,
      );
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      setState(() => _error = friendlyError(e, fallback: 'No se pudo publicar. Intenta de nuevo.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// La hora [t] en el mismo día que [day] (al editar no se cambia de día).
  static DateTime _onDay(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, fallback: 'No se pudo guardar. Intenta de nuevo.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? positiveInt(String? v) => (_amount(v) ?? 0) > 0 ? null : 'Ingresa un número mayor a 0';
    String? nonNegative(String? v) => _amount(v) != null ? null : 'Ingresa un número (0 si no sumas)';
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final money = [_ThousandsFormatter()];
    return AlertDialog(
      title: Text(widget.editBag != null
          ? 'Editar bolsa'
          : widget.editTemplate != null
              ? 'Editar bolsa recurrente'
              : _repeat
                  ? 'Bolsa recurrente'
                  : 'Publicar bolsa de hoy'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.from != null && !_editing) ...[
                  Text(widget.from!.imageUrl != null
                          ? 'Con los datos y la foto de tu última bolsa: revisa y publica (puedes elegir otra foto).'
                          : 'Con los datos de tu última bolsa: revisa y publica.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted)),
                  const SizedBox(height: 8),
                ],
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
                        inputFormatters: money,
                        decoration: const InputDecoration(labelText: 'Normal', prefixText: '\$ '),
                        validator: positiveInt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: TextInputType.number,
                        inputFormatters: money,
                        decoration: const InputDecoration(labelText: 'Oferta', prefixText: '\$ '),
                        validator: positiveInt,
                      ),
                    ),
                  ],
                ),
                // Siempre a la vista: cuánto recibe el local y la comisión de Woowfy.
                ListenableBuilder(
                  listenable: Listenable.merge([_price, _originalPrice]),
                  builder: (context, _) {
                    final price = _amount(_price.text);
                    final original = _amount(_originalPrice.text);
                    final discount = price != null && original != null && original > price && price > 0
                        ? '${((1 - price / original) * 100).round()}% de descuento · '
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        price == null || price <= 0
                            ? 'Woowfy cobra una comisión de $platformFeePercent sobre el precio de oferta.'
                            : '${discount}Recibes ${formatClp(storeShareOf(price))} por bolsa (comisión Woowfy $platformFeePercent).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(
                    labelText: widget.editBag != null ? 'Sumar unidades' : 'Cantidad de bolsas',
                    helperText: widget.editBag != null ? 'Hoy quedan ${widget.editBag!.quantityAvailable}. Deja 0 si no sumas.' : null,
                  ),
                  validator: widget.editBag != null ? nonNegative : positiveInt,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(_repeat ? 'Retiro:' : widget.editBag != null ? 'Retiro:' : 'Retiro hoy:'),
                    TextButton(onPressed: _timesLocked ? null : () => _pick(true), child: Text(_start.format(context))),
                    const Text('a'),
                    TextButton(onPressed: _timesLocked ? null : () => _pick(false), child: Text(_end.format(context))),
                  ],
                ),
                if (_timesLocked)
                  Text('Ya hay compradores: el horario queda fijo porque está en sus comprobantes.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: WoowfyColors.muted)),
                if (!_editing) SwitchListTile(
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
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving
              ? (_editing ? 'Guardando…' : 'Publicando…')
              : _editing
                  ? 'Guardar cambios'
                  : _repeat
                      ? 'Crear recurrente'
                      : 'Publicar'),
        ),
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

/// Monto escrito por el comercio: acepta "3.500" o "3500".
int? _amount(String? text) => int.tryParse((text ?? '').replaceAll('.', '').trim());

/// Deja solo dígitos y agrega el punto de miles mientras se escribe (3500 → 3.500).
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > 9) return oldValue;
    final text = _group(digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  static String _group(String digits) {
    final n = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final out = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) out.write('.');
      out.write(n[i]);
    }
    return out.toString();
  }
}
