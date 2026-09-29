import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/widgets.dart';

/// Muestra el HTML de un correo en un iframe aislado (srcdoc + sandbox), tal como lo vería el cliente.
class EmailHtmlView extends StatelessWidget {
  const EmailHtmlView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      key: ValueKey(html.hashCode),
      tagName: 'iframe',
      onElementCreated: (Object element) {
        final iframe = element as JSObject;
        // Sin scripts ni formularios; los enlaces se abren en otra pestaña.
        iframe.callMethod('setAttribute'.toJS, 'sandbox'.toJS, 'allow-popups allow-popups-to-escape-sandbox'.toJS);
        iframe.setProperty('srcdoc'.toJS, html.replaceFirst('<body', '<head><base target="_blank"></head><body').toJS);
        final style = iframe.getProperty<JSObject>('style'.toJS);
        style.setProperty('border'.toJS, '0'.toJS);
        style.setProperty('width'.toJS, '100%'.toJS);
        style.setProperty('height'.toJS, '100%'.toJS);
      },
    );
  }
}
