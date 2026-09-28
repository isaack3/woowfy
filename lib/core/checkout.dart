import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Rutas internas (checkout simulado) se abren dentro de la app; URLs externas
/// (Mercado Pago) reemplazan la pestaña actual y vuelven a /pedido/:id al terminar.
Future<void> openCheckout(BuildContext context, String url) async {
  if (url.startsWith('/')) {
    context.go(url);
  } else {
    await launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
  }
}
