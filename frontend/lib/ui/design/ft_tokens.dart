import 'package:flutter/material.dart';

class FTDesignTokens {
  const FTDesignTokens._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;

  static const double e0 = 0;
  static const double e1 = 1;
  static const double e2 = 2;
  static const double e3 = 3;

  static const Duration d150 = Duration(milliseconds: 150);
  static const Duration d220 = Duration(milliseconds: 220);
  static const Duration d300 = Duration(milliseconds: 300);

  static BorderRadius get roundedSm => BorderRadius.circular(radiusSm);
  static BorderRadius get roundedMd => BorderRadius.circular(radiusMd);
  static BorderRadius get roundedLg => BorderRadius.circular(radiusLg);

  static List<BoxShadow> elevationShadows(ColorScheme scheme, double level) {
    if (level <= e0) return const <BoxShadow>[];
    final alpha = level == e1
        ? 0.06
        : level == e2
            ? 0.09
            : 0.12;
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
    return <BoxShadow>[
      BoxShadow(
        color: scheme.shadow.withValues(alpha: alpha),
        blurRadius: blur,
        offset: offset,
      ),
    ];
  }
}
