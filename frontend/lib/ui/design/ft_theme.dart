import 'package:flutter/material.dart';

import '../foundation/theme/ft_theme.dart' as foundation;
import '../theme/theme_controller.dart';

class FTTheme {
  const FTTheme._();

  static ThemeData light(AppBackgroundPalette palette) =>
      foundation.FTTheme.light(palette);

  static ThemeData dark(AppBackgroundPalette palette) =>
      foundation.FTTheme.dark(palette);
}
