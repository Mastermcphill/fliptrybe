import 'package:flutter/material.dart';

import '../foundation/app_color_schemes.dart';
import '../theme/theme_controller.dart';
import 'ft_motion.dart';
import 'ft_tokens.dart';
import 'ft_typography.dart';

class FTTheme {
  const FTTheme._();

  static ThemeData light(AppBackgroundPalette palette) {
    final scheme = AppColorSchemes.light(palette);
    return _themeFromScheme(scheme);
  }

  static ThemeData dark(AppBackgroundPalette palette) {
    final scheme = AppColorSchemes.dark(palette);
    return _themeFromScheme(scheme);
  }

  static ThemeData _themeFromScheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: FTTypography.textTheme(scheme),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: FTDesignTokens.roundedMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: FTDesignTokens.md,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FTDesignTokens.md,
          vertical: FTDesignTokens.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedSm,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedSm,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedSm,
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: const <ThemeExtension<dynamic>>[
        _FTMotionThemeExtension(FTMotion.fast, FTMotion.normal, FTMotion.slow),
      ],
    );
  }
}

class _FTMotionThemeExtension extends ThemeExtension<_FTMotionThemeExtension> {
  const _FTMotionThemeExtension(this.fast, this.normal, this.slow);

  final Duration fast;
  final Duration normal;
  final Duration slow;

  @override
  ThemeExtension<_FTMotionThemeExtension> copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
  }) {
    return _FTMotionThemeExtension(
      fast ?? this.fast,
      normal ?? this.normal,
      slow ?? this.slow,
    );
  }

  @override
  ThemeExtension<_FTMotionThemeExtension> lerp(
    covariant ThemeExtension<_FTMotionThemeExtension>? other,
    double t,
  ) {
    if (other is! _FTMotionThemeExtension) return this;
    return _FTMotionThemeExtension(
      Duration(
          milliseconds: (fast.inMilliseconds +
                  (other.fast.inMilliseconds - fast.inMilliseconds) * t)
              .round()),
      Duration(
          milliseconds: (normal.inMilliseconds +
                  (other.normal.inMilliseconds - normal.inMilliseconds) * t)
              .round()),
      Duration(
          milliseconds: (slow.inMilliseconds +
                  (other.slow.inMilliseconds - slow.inMilliseconds) * t)
              .round()),
    );
  }
}
