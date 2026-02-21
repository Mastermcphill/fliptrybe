import 'package:flutter/material.dart';

import 'tokens/ft_colors.dart';
import '../theme/theme_controller.dart';

class AppColorSchemes {
  const AppColorSchemes._();

  static Color _seed(AppBackgroundPalette palette) => FTColors.seedFor(palette);

  static ColorScheme light(AppBackgroundPalette palette) {
    final _ = _seed(palette);
    return FTColors.lightScheme(palette);
  }

  static ColorScheme dark(AppBackgroundPalette palette) {
    final _ = _seed(palette);
    return FTColors.darkScheme(palette);
  }
}
