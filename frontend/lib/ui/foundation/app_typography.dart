import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  static TextTheme textTheme(ColorScheme scheme) {
    return TextTheme(
      headlineSmall: TextStyle(
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      displaySmall: TextStyle(
        fontSize: 20,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    );
  }

  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!;

  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle cardTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle meta(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;

  static TextStyle price(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!;
}
