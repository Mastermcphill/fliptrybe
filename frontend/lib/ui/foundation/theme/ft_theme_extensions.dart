import 'package:flutter/material.dart';

import '../tokens/ft_motion.dart';

@immutable
class FTMotionThemeExtension extends ThemeExtension<FTMotionThemeExtension> {
  const FTMotionThemeExtension({
    required this.quick,
    required this.standard,
    required this.emphasized,
  });

  final Duration quick;
  final Duration standard;
  final Duration emphasized;

  static const FTMotionThemeExtension defaults = FTMotionThemeExtension(
    quick: FTMotion.quick,
    standard: FTMotion.standard,
    emphasized: FTMotion.emphasized,
  );

  @override
  FTMotionThemeExtension copyWith({
    Duration? quick,
    Duration? standard,
    Duration? emphasized,
  }) {
    return FTMotionThemeExtension(
      quick: quick ?? this.quick,
      standard: standard ?? this.standard,
      emphasized: emphasized ?? this.emphasized,
    );
  }

  @override
  ThemeExtension<FTMotionThemeExtension> lerp(
    covariant ThemeExtension<FTMotionThemeExtension>? other,
    double t,
  ) {
    if (other is! FTMotionThemeExtension) return this;
    return FTMotionThemeExtension(
      quick: _lerpDuration(quick, other.quick, t),
      standard: _lerpDuration(standard, other.standard, t),
      emphasized: _lerpDuration(emphasized, other.emphasized, t),
    );
  }

  Duration _lerpDuration(Duration a, Duration b, double t) {
    return Duration(
      milliseconds:
          (a.inMilliseconds + ((b.inMilliseconds - a.inMilliseconds) * t))
              .round(),
    );
  }
}
