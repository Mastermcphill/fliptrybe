import 'package:flutter/material.dart';

class AppTokens {
  const AppTokens._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;

  static const Duration d150 = Duration(milliseconds: 150);
  static const Duration d200 = Duration(milliseconds: 200);
  static const Duration d300 = Duration(milliseconds: 300);

  static const double e0 = 0;
  static const double e1 = 1;
  static const double e2 = 2;
  static const double e3 = 3;

  static List<BoxShadow> elevationShadows(ColorScheme scheme, double level) {
    if (level <= e0) return const [];
    final opacity = level == e1
        ? 0.06
        : level == e2
            ? 0.08
            : 0.1;
    final blur = level == e1
        ? 8.0
        : level == e2
            ? 12.0
            : 16.0;
    final offset = level == e1
        ? const Offset(0, 2)
        : level == e2
            ? const Offset(0, 4)
            : const Offset(0, 6);
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: opacity),
        blurRadius: blur,
        offset: offset,
      ),
    ];
  }
}
