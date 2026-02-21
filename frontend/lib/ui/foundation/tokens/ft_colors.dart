import 'package:flutter/material.dart';

import '../../theme/theme_controller.dart';

class FTColors {
  const FTColors._();

  static const Color success = Color(0xFF157347);
  static const Color warning = Color(0xFF9A6700);
  static const Color error = Color(0xFFB3261E);

  static Color seedFor(AppBackgroundPalette palette) {
    switch (palette) {
      case AppBackgroundPalette.mint:
        return const Color(0xFF0E8A75);
      case AppBackgroundPalette.sand:
        return const Color(0xFF8C6A3D);
      case AppBackgroundPalette.neutral:
        return const Color(0xFF3C5A99);
    }
  }

  static ColorScheme lightScheme(AppBackgroundPalette palette) {
    final base = ColorScheme.fromSeed(
      seedColor: seedFor(palette),
      brightness: Brightness.light,
    );
    switch (palette) {
      case AppBackgroundPalette.mint:
        return base.copyWith(
          surface: const Color(0xFFF5FBF9),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFE4F5EF),
          secondaryContainer: const Color(0xFFD7F0E7),
        );
      case AppBackgroundPalette.sand:
        return base.copyWith(
          surface: const Color(0xFFFCF9F5),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFF2E6D8),
          secondaryContainer: const Color(0xFFF4E4CF),
        );
      case AppBackgroundPalette.neutral:
        return base.copyWith(
          surface: const Color(0xFFF7F9FD),
          surfaceContainerLow: const Color(0xFFFFFFFF),
          surfaceContainerHighest: const Color(0xFFE7EDF8),
          secondaryContainer: const Color(0xFFDCE5F8),
        );
    }
  }

  static ColorScheme darkScheme(AppBackgroundPalette palette) {
    final base = ColorScheme.fromSeed(
      seedColor: seedFor(palette),
      brightness: Brightness.dark,
    );
    switch (palette) {
      case AppBackgroundPalette.mint:
        return base.copyWith(
          surface: const Color(0xFF0F1714),
          surfaceContainerLow: const Color(0xFF17231F),
          surfaceContainerHighest: const Color(0xFF24352E),
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
          surfaceContainerHighest: const Color(0xFF253143),
          secondaryContainer: const Color(0xFF2E3950),
        );
    }
  }
}
