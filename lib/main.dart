import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/analytics.dart';
import 'core/backend.dart';
import 'core/push.dart';
import 'features/auth/login_page.dart' show ensureUserProfile;
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En la web, Flutter no expone nada a los lectores de pantalla hasta que alguien toca un botón oculto
  // ("Enable accessibility"). Lo activamos desde el inicio.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  // URLs limpias en web (app.woowfy.com/bag/123 en vez de /#/bag/123).
  usePathUrlStrategy();
  await initializeDateFormatting('es_CL');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Los emuladores se conectan antes de usar Auth: si no, la sesión guardada se valida contra producción y se pierde
  // al recargar.
  if (useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    functions.useFunctionsEmulator('localhost', 5001);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
  }
  // Correos de Firebase Auth (p. ej. recuperar contraseña) en español.
  await FirebaseAuth.instance.setLanguageCode('es');
  // Espera a que Firebase restaure la sesión guardada: si no, al abrir directo una ruta protegida
  // (p. ej. /merchant) el router vería "sin sesión" y mandaría al login.
  await FirebaseAuth.instance.authStateChanges().first;
  // Vuelta de un ingreso con Google por redirección (cuando el navegador bloqueó la ventana emergente).
  if (kIsWeb) {
    try {
      final user = (await FirebaseAuth.instance.getRedirectResult()).user;
      if (user != null) await ensureUserProfile(user);
    } catch (_) {}
  }
  Push.listenInForeground();
  Analytics.trackOncePerSession('app_visit');
  runApp(const WoowfyApp());
}
