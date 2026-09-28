import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';

class WoowfyApp extends StatelessWidget {
  const WoowfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Woowfy',
      debugShowCheckedModeBanner: false,
      theme: WoowfyTheme.light,
      darkTheme: WoowfyTheme.dark,
      routerConfig: appRouter,
    );
  }
}
