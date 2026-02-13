import 'package:flutter/material.dart';

import 'theme_controller.dart';

class AppTheme {
  static Color _seed(AppBackgroundPalette palette) {
    switch (palette) {
      case AppBackgroundPalette.mint:
        return const Color(0xFF0E7490);
      case AppBackgroundPalette.sand:
        return const Color(0xFF9A6B2E);
      case AppBackgroundPalette.neutral:
        return const Color(0xFF1D4ED8);
    }
  }

  static ThemeData light(AppBackgroundPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed(palette),
      brightness: Brightness.light,
    );
    return _baseTheme(scheme);
  }

  static ThemeData dark(AppBackgroundPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed(palette),
      brightness: Brightness.dark,
    );
    return _baseTheme(scheme);
  }

  static ThemeData _baseTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
