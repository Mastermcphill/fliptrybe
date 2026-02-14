import 'package:flutter/material.dart';

class FTTypography {
  const FTTypography._();

  static TextTheme textTheme(ColorScheme scheme) {
    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant,
      ),
      displaySmall: TextStyle(
        fontSize: 21,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    );
  }

  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!;

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!;

  static TextStyle muted(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;
}
