import 'package:flutter/services.dart';

class FTHaptics {
  const FTHaptics._();

  static Future<void> lightTap() => HapticFeedback.lightImpact();

  static Future<void> selection() => HapticFeedback.selectionClick();

  static Future<void> success() => HapticFeedback.mediumImpact();
}
