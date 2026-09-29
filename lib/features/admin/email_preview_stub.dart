import 'package:flutter/widgets.dart';

/// Fuera de la web no hay vista previa (el panel admin es solo web).
class EmailHtmlView extends StatelessWidget {
  const EmailHtmlView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) => const Center(child: Text('Vista previa disponible solo en la web.'));
}
