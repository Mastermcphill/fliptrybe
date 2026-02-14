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

  static BorderRadius get roundedSm => BorderRadius.circular(radiusSm);
  static BorderRadius get roundedMd => BorderRadius.circular(radiusMd);
  static BorderRadius get roundedLg => BorderRadius.circular(radiusLg);
}
