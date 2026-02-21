import 'package:flutter/widgets.dart';

/// 8pt spatial rhythm used across layouts.
class FTSpacing {
  const FTSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 40;

  static const EdgeInsets page = EdgeInsets.all(sm);
  static const EdgeInsets section = EdgeInsets.all(md);
  static const EdgeInsets card = EdgeInsets.all(sm);
}
