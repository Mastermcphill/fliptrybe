import 'package:flutter/animation.dart';

class FTMotion {
  const FTMotion._();

  static const Duration quick = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve standardCurve = Curves.easeInOutCubic;
}
