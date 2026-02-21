import 'package:flutter/material.dart';

import '../foundation/tokens/ft_motion.dart';
import '../foundation/tokens/ft_radius.dart';
import '../foundation/tokens/ft_shadows.dart';
import '../foundation/tokens/ft_spacing.dart';

class FTDesignTokens {
  const FTDesignTokens._();

  static const double xs = FTSpacing.xs;
  static const double sm = 12;
  static const double md = FTSpacing.sm;
  static const double lg = FTSpacing.md;
  static const double xl = FTSpacing.lg;

  static const double radiusSm = FTRadius.sm;
  static const double radiusMd = FTRadius.md;
  static const double radiusLg = 20;

  static const double e0 = 0;
  static const double e1 = 1;
  static const double e2 = 2;
  static const double e3 = 3;

  static const Duration d150 = FTMotion.quick;
  static const Duration d220 = FTMotion.emphasized;
  static const Duration d300 = FTMotion.slow;

  static BorderRadius get roundedSm => BorderRadius.circular(radiusSm);
  static BorderRadius get roundedMd => BorderRadius.circular(radiusMd);
  static BorderRadius get roundedLg => BorderRadius.circular(radiusLg);

  static List<BoxShadow> elevationShadows(ColorScheme scheme, double level) {
    if (level <= e0) return const <BoxShadow>[];
    if (level == e1) return FTShadows.subtle(scheme);
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
