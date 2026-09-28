import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';

class WoowfyApp extends StatelessWidget {
  const WoowfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Woowfy',
      debugShowCheckedModeBanner: false,
      // La identidad de marca es clara (crema + verde); por ahora sin modo oscuro.
      theme: WoowfyTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      scaffoldMessengerKey: scaffoldMessengerKey,
      // Español de Chile: hora de 24 h, calendarios y textos del sistema en español.
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
