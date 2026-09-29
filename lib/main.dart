import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/backend.dart';
import 'core/push.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // URLs limpias en web (app.woowfy.com/bag/123 en vez de /#/bag/123).
  usePathUrlStrategy();
  await initializeDateFormatting('es_CL');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Correos de Firebase Auth (p. ej. recuperar contraseña) en español.
  await FirebaseAuth.instance.setLanguageCode('es');
  if (useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    functions.useFunctionsEmulator('localhost', 5001);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
  }
  // Espera a que Firebase restaure la sesión guardada: si no, al abrir directo una ruta protegida
  // (p. ej. /merchant) el router vería "sin sesión" y mandaría al login.
  await FirebaseAuth.instance.authStateChanges().first;
  Push.listenInForeground();
  runApp(const WoowfyApp());
}
