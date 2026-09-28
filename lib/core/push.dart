import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';

/// Clave pública web push (VAPID) de Firebase Cloud Messaging.
/// Se genera en consola → Configuración del proyecto → Cloud Messaging → Certificados push web.
/// Es pública (no es un secreto). Mientras esté vacía, las notificaciones se muestran como "próximamente".
const webPushVapidKey = '';

/// Para mostrar avisos en pantalla cuando llega una notificación con la app abierta.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class Push {
  Push._();

  static bool get configured => webPushVapidKey.isNotEmpty;

  /// Pide permiso, obtiene el token de este navegador y lo guarda en el usuario.
  /// Devuelve null si todo salió bien o un mensaje de error para mostrar.
  static Future<String?> enable(String uid) async {
    if (!configured) return 'Las notificaciones estarán disponibles muy pronto.';
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return 'Bloqueaste las notificaciones. Actívalas en la configuración del navegador (ícono del candado).';
      }
      final token = await FirebaseMessaging.instance.getToken(vapidKey: webPushVapidKey);
      if (token == null) return 'Tu navegador no entregó un token de notificaciones.';
      await Repository.instance.addPushToken(uid, token);
      return null;
    } catch (e) {
      return 'No pudimos activar las notificaciones en este navegador ($e).';
    }
  }

  static Future<void> disable(String uid) async {
    if (!configured) return;
    final token = await FirebaseMessaging.instance.getToken(vapidKey: webPushVapidKey);
    if (token != null) await Repository.instance.removePushToken(uid, token);
    await FirebaseMessaging.instance.deleteToken();
  }

  /// Con la app abierta, el navegador no muestra la notificación: la mostramos como aviso.
  static void listenInForeground() {
    if (!configured) return;
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Text([n.title, n.body].whereType<String>().join('\n')),
        duration: const Duration(seconds: 6),
      ));
    });
  }
}
