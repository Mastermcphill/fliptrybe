import 'package:flutter/material.dart';

class FTTokens {
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;

  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 16;
  static const double spaceLg = 24;

  static const Color bg = Color(0xFFF6F8FB);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color accent = Color(0xFF0E7490);
  static const Color success = Color(0xFF0F766E);
  static const Color warn = Color(0xFFB45309);
  static const Color danger = Color(0xFFB91C1C);

  static List<BoxShadow> get shadowSm => const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ];
}
