import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';

class AppColorSchemes {
  const AppColorSchemes._();

  static Color _seed(AppBackgroundPalette palette) {
    switch (palette) {
      case AppBackgroundPalette.mint:
        return const Color(0xFF0E8A75);
      case AppBackgroundPalette.sand:
        return const Color(0xFF8C6A3D);
      case AppBackgroundPalette.neutral:
        return const Color(0xFF3C5A99);
    }
  }

  static ColorScheme light(AppBackgroundPalette palette) {
    final base = ColorScheme.fromSeed(
      seedColor: _seed(palette),
      brightness: Brightness.light,
    );
    switch (palette) {
      case AppBackgroundPalette.mint:
        return base.copyWith(
          surface: const Color(0xFFF4FBF8),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFE5F4EE),
          secondaryContainer: const Color(0xFFD7F0E7),
        );
      case AppBackgroundPalette.sand:
        return base.copyWith(
          surface: const Color(0xFFFCF8F3),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFF1E4D7),
          secondaryContainer: const Color(0xFFF4E4CF),
        );
      case AppBackgroundPalette.neutral:
        return base.copyWith(
          surface: const Color(0xFFF6F8FC),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFE8EDF6),
          secondaryContainer: const Color(0xFFDEE6F5),
        );
    }
  }

  static ColorScheme dark(AppBackgroundPalette palette) {
    final base = ColorScheme.fromSeed(
      seedColor: _seed(palette),
      brightness: Brightness.dark,
    );
    switch (palette) {
      case AppBackgroundPalette.mint:
        return base.copyWith(
          surface: const Color(0xFF0F1714),
          surfaceContainerLow: const Color(0xFF17231F),
          surfaceContainerHighest: const Color(0xFF22322C),
          secondaryContainer: const Color(0xFF234137),
        );
      case AppBackgroundPalette.sand:
        return base.copyWith(
          surface: const Color(0xFF17130E),
          surfaceContainerLow: const Color(0xFF231D16),
          surfaceContainerHighest: const Color(0xFF31281D),
          secondaryContainer: const Color(0xFF413524),
        );
      case AppBackgroundPalette.neutral:
        return base.copyWith(
          surface: const Color(0xFF11141B),
          surfaceContainerLow: const Color(0xFF181E28),
          surfaceContainerHighest: const Color(0xFF263041),
          secondaryContainer: const Color(0xFF2E3950),
        );
    }
  }
}
