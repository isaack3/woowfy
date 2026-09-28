import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta oficial (brand/07-colors) + tonos de apoyo.
class WoowfyColors {
  static const green = Color(0xFF063B25);
  static const green2 = Color(0xFF0B5A39);
  static const lime = Color(0xFF9BE52C);
  static const limeSoft = Color(0xFFE6F8CC);
  static const coral = Color(0xFFFF694D);
  static const orange = Color(0xFFFF9B4A);
  static const orangeSoft = Color(0xFFFFE7D1);
  static const cream = Color(0xFFFFF7E3);
  static const black = Color(0xFF101713);
  static const muted = Color(0xFF4E5A53);
  static const line = Color(0xFFEBDFC3);
}

/// Propuesta A "Verde profundo": encabezados verde oscuro, fondo crema, tarjetas blancas y acentos lima.
/// Colores fijos de la marca (sin generar tonos automáticos de Material).
class WoowfyTheme {
  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: WoowfyColors.green,
      onPrimary: WoowfyColors.cream,
      primaryContainer: WoowfyColors.limeSoft,
      onPrimaryContainer: WoowfyColors.green,
      secondary: WoowfyColors.lime,
      onSecondary: WoowfyColors.green,
      secondaryContainer: WoowfyColors.limeSoft,
      onSecondaryContainer: WoowfyColors.green,
      tertiary: WoowfyColors.coral,
      onTertiary: Colors.white,
      tertiaryContainer: WoowfyColors.orangeSoft,
      onTertiaryContainer: Color(0xFF7A3510),
      error: Color(0xFFB83A22),
      onError: Colors.white,
      surface: WoowfyColors.cream,
      onSurface: WoowfyColors.black,
      onSurfaceVariant: WoowfyColors.muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Colors.white,
      surfaceContainerHighest: Color(0xFFF6EDD6),
      outline: WoowfyColors.line,
      outlineVariant: WoowfyColors.line,
    );

    final base = ThemeData(colorScheme: scheme, useMaterial3: true, scaffoldBackgroundColor: WoowfyColors.cream);
    final text = GoogleFonts.latoTextTheme(base.textTheme).apply(
      bodyColor: WoowfyColors.black,
      displayColor: WoowfyColors.green,
    );
    final heavy = text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: WoowfyColors.green),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: WoowfyColors.green),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: WoowfyColors.green),
    );
    const pill = StadiumBorder();
    const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      side: BorderSide(color: WoowfyColors.line),
    );

    return base.copyWith(
      textTheme: heavy,
      appBarTheme: AppBarTheme(
        backgroundColor: WoowfyColors.green,
        foregroundColor: WoowfyColors.cream,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: heavy.titleLarge?.copyWith(color: WoowfyColors.cream),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: WoowfyColors.lime,
        unselectedLabelColor: WoowfyColors.cream,
        indicatorColor: WoowfyColors.lime,
        dividerColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: WoowfyColors.green,
        indicatorColor: WoowfyColors.lime,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? WoowfyColors.green : WoowfyColors.cream,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              color: s.contains(WidgetState.selected) ? WoowfyColors.lime : WoowfyColors.cream,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            )),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: WoowfyColors.green,
        indicatorColor: WoowfyColors.lime,
        selectedIconTheme: IconThemeData(color: WoowfyColors.green),
        unselectedIconTheme: IconThemeData(color: WoowfyColors.cream),
        selectedLabelTextStyle: TextStyle(color: WoowfyColors.lime, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: TextStyle(color: WoowfyColors.cream),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: WoowfyColors.lime,
          foregroundColor: WoowfyColors.green,
          disabledBackgroundColor: WoowfyColors.line,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WoowfyColors.green,
          side: const BorderSide(color: WoowfyColors.green, width: 1.4),
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: WoowfyColors.green, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: WoowfyColors.lime,
        foregroundColor: WoowfyColors.green,
        shape: StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: WoowfyColors.green,
          selectedForegroundColor: WoowfyColors.cream,
          backgroundColor: Colors.white,
          foregroundColor: WoowfyColors.green,
          side: const BorderSide(color: WoowfyColors.line),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: WoowfyColors.limeSoft,
        labelStyle: TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w700),
        side: BorderSide.none,
        shape: StadiumBorder(),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: WoowfyColors.line, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: WoowfyColors.green, width: 1.8),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WoowfyColors.green : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? WoowfyColors.lime : null),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: WoowfyColors.green,
        contentTextStyle: TextStyle(color: WoowfyColors.cream),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: WoowfyColors.cream),
      dividerTheme: const DividerThemeData(color: WoowfyColors.line),
      badgeTheme: const BadgeThemeData(backgroundColor: WoowfyColors.coral),
    );
  }
}

/// Logo (isotipo + "woowfy"). En fondos verdes usar [onDark].
class WoowfyLogo extends StatelessWidget {
  const WoowfyLogo({super.key, this.size = 28, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/brand/woowfy-isotipo.png', height: size, semanticLabel: 'Woowfy'),
        const SizedBox(width: 6),
        Text(
          'woowfy',
          style: GoogleFonts.lato(
            fontSize: size * 0.9,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: onDark ? WoowfyColors.cream : WoowfyColors.green,
          ),
        ),
      ],
    );
  }
}

/// Etiqueta de descuento (pastilla lima).
class DiscountPill extends StatelessWidget {
  const DiscountPill(this.percent, {super.key});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const ShapeDecoration(color: WoowfyColors.lime, shape: StadiumBorder()),
      child: Text('-$percent%', style: const TextStyle(color: WoowfyColors.green, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}
