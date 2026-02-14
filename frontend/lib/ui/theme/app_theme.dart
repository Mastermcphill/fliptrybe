import 'package:flutter/material.dart';

import '../design/ft_theme.dart';
import 'theme_controller.dart';

class AppTheme {
  static ThemeData light(AppBackgroundPalette palette) =>
      FTTheme.light(palette);

  static ThemeData dark(AppBackgroundPalette palette) => FTTheme.dark(palette);
}
