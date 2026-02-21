import 'package:flutter/material.dart';

import '../foundation/tokens/ft_motion.dart' as foundation;

class FTMotion {
  const FTMotion._();

  static const Duration fast = foundation.FTMotion.quick;
  static const Duration normal = foundation.FTMotion.emphasized;
  static const Duration slow = foundation.FTMotion.slow;

  static const Curve easeOut = foundation.FTMotion.easeOut;
  static const Curve easeIn = foundation.FTMotion.easeIn;
  static const Curve standard = foundation.FTMotion.standardCurve;
}
