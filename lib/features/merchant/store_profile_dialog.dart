import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../data/chile.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../bags/bag_image.dart';

/// El comercio edita su perfil: logo, categoría, descripción, horario y datos de contacto.
class StoreProfileDialog extends StatefulWidget {
  const StoreProfileDialog({super.key, required this.store});

  final Store store;

  @override
  State<StoreProfileDialog> createState() => _StoreProfileDialogState();
}

class _StoreProfileDialogState extends State<StoreProfileDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.store.name);
  late final _description = TextEditingController(text: widget.store.description);
  late final _hours = TextEditingController(text: widget.store.hours);
  late final _address = TextEditingController(text: widget.store.address);
  late final _comuna = TextEditingController(text: widget.store.comuna);
  late final _phone = TextEditingController(text: widget.store.phone ?? '');
  late String? _category = widget.store.category;
  late String? _region = chileRegions.contains(widget.store.region) ? widget.store.region : null;
  Uint8List? _logo;
  String _logoType = 'image/jpeg';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _description, _hours, _address, _comuna, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _logo = bytes;
      _logoType = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = Repository.instance;
      final logoUrl = _logo == null ? widget.store.logoUrl : await repo.uploadStoreLogo(widget.store.ownerUid, _logo!, _logoType);
      await repo.updateStoreProfile(widget.store.id, {
        'name': _name.text.trim(),
        'category': _category,
        'description': _description.text.trim(),
        'hours': _hours.text.trim(),
        'address': _address.text.trim(),
        'comuna': _comuna.text.trim(),
        'region': _region,
        'phone': _phone.text.trim(),
        'logoUrl': logoUrl,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;
    return AlertDialog(
      title: const Text('Perfil del local'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _saving ? null : _pickLogo,
                  customBorder: const CircleBorder(),
                  child: Stack(children: [
                    _logo != null
                        ? CircleAvatar(radius: 44, backgroundImage: MemoryImage(_logo!))
                        : StoreLogo(url: widget.store.logoUrl, size: 88),
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 15,
                        backgroundColor: WoowfyColors.green,
                        child: Icon(Icons.photo_camera_outlined, size: 16, color: WoowfyColors.cream),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                const Text('Logo o foto del local', style: TextStyle(fontSize: 12, color: WoowfyColors.muted)),
                const SizedBox(height: 16),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre del local'), validator: required),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: storeCategories.contains(_category) ? _category : null,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [for (final c in storeCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v),
                  validator: (v) => v == null ? 'Elige una categoría' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  maxLength: 280,
                  decoration: const InputDecoration(labelText: 'Descripción', hintText: 'Pan de masa madre y pastelería artesanal'),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _hours,
                  decoration: const InputDecoration(labelText: 'Horario de atención', hintText: 'Lun a sáb, 8:00 – 21:00'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _region,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Región'),
                  items: [for (final r in chileRegions) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => _region = v),
                  validator: (v) => v == null ? 'Elige una región' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _comuna, decoration: const InputDecoration(labelText: 'Comuna'), validator: required),
                const SizedBox(height: 12),
                TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Dirección'), validator: required),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono de contacto'),
                  validator: required,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
      ],
    );
  }
}
