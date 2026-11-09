import 'package:flutter/material.dart';

/// Semantic colours that keep the same meaning across both apps.
class KiranaColors {
  static const seed = Color(0xFF0F766E);
  static const dues = Color(0xFFB42318);
  static const received = Color(0xFF067647);
  static const warning = Color(0xFFB54708);
}

ThemeData kiranaTheme({Brightness brightness = Brightness.light}) {
  final scheme = ColorScheme.fromSeed(seedColor: KiranaColors.seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(centerTitle: false, scrolledUnderElevation: 1),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
