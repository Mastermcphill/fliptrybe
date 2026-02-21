import 'package:flutter/material.dart';

import '../../theme/theme_controller.dart';
import '../tokens/ft_colors.dart';
import '../tokens/ft_motion.dart';
import '../tokens/ft_radius.dart';
import '../tokens/ft_shadows.dart';
import '../tokens/ft_spacing.dart';
import '../tokens/ft_typography.dart';
import 'ft_theme_extensions.dart';

class FTTheme {
  const FTTheme._();

  static ThemeData light(AppBackgroundPalette palette) {
    return _themeFromScheme(FTColors.lightScheme(palette));
  }

  static ThemeData dark(AppBackgroundPalette palette) {
    return _themeFromScheme(FTColors.darkScheme(palette));
  }

  static ThemeData _themeFromScheme(ColorScheme scheme) {
    final textTheme = FTTypography.textTheme(scheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: FTRadius.roundedMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FTSpacing.sm,
          vertical: FTSpacing.xs,
        ),
        border: OutlineInputBorder(
          borderRadius: FTRadius.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FTRadius.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FTRadius.roundedMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: FTRadius.roundedMd,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: FTRadius.roundedMd,
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: FTRadius.roundedMd),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: FTSpacing.sm,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FTSpacing.sm,
          vertical: FTSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: FTRadius.roundedMd,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        elevation: 0,
        selectedLabelStyle:
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelMedium,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: FTRadius.roundedLg),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FTFadeSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: FTFadeSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: FTFadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: FTFadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: FTFadeSlidePageTransitionsBuilder(),
        },
      ),
      splashFactory: InkRipple.splashFactory,
      extensions: const <ThemeExtension<dynamic>>[
        FTMotionThemeExtension.defaults,
      ],
    );
  }
}

class FTFadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FTFadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == Navigator.defaultRouteName) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: FTMotion.easeOut,
      reverseCurve: FTMotion.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

BoxDecoration ftCardDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: scheme.surfaceContainerLow,
    borderRadius: FTRadius.roundedMd,
    border: Border.all(color: scheme.outlineVariant),
    boxShadow: FTShadows.subtle(scheme),
  );
}
